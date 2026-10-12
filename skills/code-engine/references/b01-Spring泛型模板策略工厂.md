***

name: b01-Spring 泛型模板策略工厂

description: Java/Spring 下的强设计模式组合 ——Spring 自动初始化 + 泛型抽象模板基类 + 策略工厂。用泛型参数声明 "该策略处理什么数据"，Spring 自动实例化全部策略实现并在初始化时完成注册，运行时按 key / 类型分发，零 if-else。涉及 "策略工厂怎么写 / 父类解析子类泛型 / Spring 自动收集策略 Bean / CGLIB 代理泛型失败 / 静态注册表 /key 重复覆盖" 时读取。



***

# b01 Spring + 泛型 + 抽象模板 + 策略工厂

> 语言 / 框架特定的功能工程化意向（Java + Spring）。
> 案例脉络：一个原型实现 → 在 Spring 代理与生命周期上踩坑 → 工程化正解。

## 一、模式意向

**场景**：同一族业务有 N 种处理分支（N 种 WebSocket 消息、N 种游戏操作、N 种事件、N 种支付渠道），每个分支处理的数据类型不同。

**要达到的效果**：



1. **泛型声明职责**：策略子类用泛型实参 `T` 声明 "我处理什么数据"，如 `ChatHandler extends TypedMessageHandler<ChatMessage>`；

2. **抽象模板收敛公共流程**：泛型基类把反序列化、校验、事务、日志等公共步骤做掉，子类只实现一个业务方法；

3. **Spring 自动初始化**：所有策略实现标 `@Component`，Spring 自动调用构造函数完成实例化，不需要手工 new、不需要手工登记；

4. **初始化即注册**：容器启动期间，每个 "策略实例 + 它处理的 key / 数据类型" 自动进入工厂注册表；

5. **运行时按 key 取策略**：调用方一行 `factory.get(key).execute(data)`，新增分支只加一个类，调用方与工厂代码零改动。

模式角色对应：



| 角色     | 承担                                          |
| ------ | ------------------------------------------- |
| 策略接口   | 声明 key（我处理哪类消息）与统一入口                        |
| 泛型抽象模板 | 基类 `AbstractXxxHandler<T>`，实现公共流程，留一个抽象业务方法 |
| 具体策略   | `@Component` 子类，指定泛型实参 + 实现业务方法             |
| 策略工厂   | 持有注册表，按 key / 类型解析策略；由 Spring 装配            |

## 二、原型写法（设计意向的原始写法）



```
// 泛型抽象策略：父类构造器解析子类泛型，并自注册进静态工厂
public abstract class EventStrategy<T> {

    protected Class<T> tClass;

    public EventStrategy(String key) {
        this.tClass = resolveGenericClass();   // 父类构造器解析子类实现的泛型
        EventStrategyFactory.register(key, this);   // 构造期自注册
    }

    @SuppressWarnings("unchecked")
    private Class<T> resolveGenericClass() {
        try {
            return (Class<T>) ((ParameterizedType) getClass()
                    .getGenericSuperclass())
                    .getActualTypeArguments()[0];
        } catch (Exception e) {
            return (Class<T>) Object.class;   // ← 坑：解析失败静默降级
        }
    }

    public void execute(Object obj) {
        if (tClass.isInstance(obj)) execute0(tClass.cast(obj));
    }

    abstract void execute0(T o);
}

// 静态工厂
public class EventStrategyFactory {
    private static final Map<String, EventStrategy<?>> cache = new ConcurrentHashMap<>();
    public static void register(String type, EventStrategy<?> s) { cache.put(type, s); }
    public static EventStrategy<?> getStrategy(String type) { return cache.get(type); }
}
```

另一处原型用 `@PostConstruct` 注册（`AbstractGamingHandler<Req>`）：



```
@PostConstruct
private void init() {
    ParameterizedType p = (ParameterizedType) this.getClass().getGenericSuperclass();
    this.bodyClass = (Class<Req>) p.getActualTypeArguments()[0];
    GamingHandlerFactory.register(getTypeEnum().getStatus(), this);
}
```

**这就是 "Spring 自动调用构造函数 → 父类解析子类泛型 → 初始化时注册带泛型的策略" 的原型。** 意向正确，但工程化落地有四个真实的坑。

## 三、工程化四坑（重构记录）

### 坑 1：父类构造器 / 初始化方法反射解析泛型，撞上 Spring CGLIB 代理

Spring 为加了 `@Transactional`、`@Async`、AOP 的 Bean 创建 CGLIB 代理子类。此时 `this.getClass()` 是 `XxxService$$EnhancerBySpringCGLIB$$...`，在构造器里 `getGenericSuperclass()` 逐层上溯取泛型，**会拿到代理层的泛型签名而失败**（ClassCastException、取到错误的类型参数位置、多层继承时上溯中断）。

> 重构注释原文：
> "**去掉了反射解析泛型的构造器。** 原版在无参构造里用 getGenericSuperclass () 逐层上溯取实体类型，Spring CGLIB 代理类上会拿到代理的泛型而失败。现在要求子类显式传入 entityClass，编译期就能发现错误。"

### 坑 2：静态 Map + 构造期自注册 = 全局可变状态

`static Map` + `register(key, this)` 本质是 a01 禁止的全局存储：



* 构造期 `this` 逃逸进静态表，对象尚未构造完成就被别处可见；

* 单元测试之间注册表互相污染，无法重置；

* 插件 / 多类加载器场景静态表泄漏；

* 容器看不到这张表，策略 Bean 即使被销毁，注册表里仍挂着失效实例。

### 坑 3：静默降级与静默覆盖



* 泛型解析失败 → 降级 `Object.class`，类型校验形同虚设，问题推迟到业务数据进来才爆；

* `cache.put(key, s)` 后注册的策略**静默覆盖**先注册的，先写的功能整体失效，排查时很难想到是注册覆盖；

* 策略类忘了加 `@Component` → Spring 不构造它 → 永不注册，无任何报错。

### 坑 4：字段注入

原型用 `@Autowired` 字段注入：依赖不可见、无法 final、脱离容器无法实例化、循环依赖被掩盖。

## 四、正解：工厂 Bean 收集 + 显式泛型 + fail-fast

### 结构总览



```
策略接口 MessageHandler（type() + handle()）
  └─ 泛型抽象模板 TypedMessageHandler<T>（公共反序列化流程，子类传 Class）
       ├─ ChatHandler   extends TypedMessageHandler<ChatMessage>   @Component
       └─ JoinHandler   extends TypedMessageHandler<JoinMessage>   @Component
工厂 MessageDispatcher（Spring Bean，构造器注入 List<MessageHandler> 自动收集全部策略）
```

### 1. 策略接口



```
public interface MessageHandler {
    /** 该策略处理的消息类型 key */
    String type();
    /** 统一入口 */
    void handle(WebSocketSession session, JsonNode payload);
}
```

### 2. 泛型抽象模板基类（公共流程做掉，泛型 Class 显式传入）



```
public abstract class TypedMessageHandler<T> implements MessageHandler {

    private final String type;
    private final Class<T> payloadType;

    protected TypedMessageHandler(String type, Class<T> payloadType) {
        this.type = type;
        this.payloadType = payloadType;
    }

    @Override
    public String type() {
        return type;
    }

    @Override
    public void handle(WebSocketSession session, JsonNode payload) {
        // 模板做掉「JsonNode → 业务对象」；payload 已是树模型，用 convert 而非重新 parse
        T body = (payload == null || payload.isNull())
                ? null
                : Jsons.convert(payload, payloadType);
        onMessage(session, body);
    }

    /** 子类只实现这一个业务方法 */
    protected abstract void onMessage(WebSocketSession session, T payload);
}
```

### 3. 具体策略：构造器注入依赖 + 指定泛型



```
@Component
public class ChatHandler extends TypedMessageHandler<ChatMessage> {

    private final WebSocketSessionManager sessionManager;

    public ChatHandler(WebSocketSessionManager sessionManager) {
        super("chat", ChatMessage.class);   // key + 泛型 Class，编译期可见
        this.sessionManager = sessionManager;
    }

    @Override
    protected void onMessage(WebSocketSession session, ChatMessage message) {
        sessionManager.sendToUser(message.getToUserId(),
                WSMessage.of("chat", buildReply(message)));
    }
}
```

### 4. 策略工厂：Spring 构造器注入 List，自动收集、fail-fast 注册



```
@Slf4j
public class MessageDispatcher {

    private final Map<String, MessageHandler> handlers = new ConcurrentHashMap<>();

    /** Spring 把容器内所有 MessageHandler Bean 自动收进 List 注入 */
    public MessageDispatcher(List<MessageHandler> allHandlers) {
        for (MessageHandler handler : allHandlers) {
            String type = handler.type();
            if (type == null || type.isBlank()) {
                throw new IllegalStateException(
                        handler.getClass().getName() + " 没有声明 type()");
            }
            MessageHandler previous = handlers.putIfAbsent(type, handler);
            if (previous != null) {
                // 重复 key 直接启动失败，绝不允许后注册静默覆盖
                throw new IllegalStateException("消息类型 '" + type + "' 被两个处理器声明: "
                        + previous.getClass().getName() + " 与 " + handler.getClass().getName());
            }
        }
        log.info("已注册的消息处理器: {}", handlers.keySet());
    }

    public void dispatch(WebSocketSession session, WSMessage<JsonNode> message) {
        MessageHandler handler = handlers.get(message.type());
        if (handler == null) {
            throw new IllegalStateException("无处理器，type=" + message.type());
        }
        handler.handle(session, message.data());
    }
}
```

工厂本身注册为 Bean（`@Bean` 或在 AutoConfiguration 里声明）。**新增第 N 种消息：只加一个&#x20;**`@Component`**&#x20;子类，工厂、调用方零改动。**

与原型的本质差异：



| 点        | 原型                       | 正解                               |
| -------- | -------------------------------- | ----------------------------------- |
| 谁收集策略    | 策略构造器自注册进静态表                     | Spring 注入 `List<策略>`，工厂构造器注册（无静态状态） |
| 泛型 Class | 构造器 `getGenericSuperclass()` 反射猜 | 子类构造显式传 Class，编译期可见                 |
| key 重复   | `put` 静默覆盖                       | `putIfAbsent` + 启动失败                |
| key 缺失   | 取到 null 运行期 NPE                  | 构造期校验启动失败                           |
| 依赖注入     | 字段注入                             | 构造器注入 final                         |

## 五、不想手写 Class？—— 工厂侧 ResolvableType 自动解析（可穿透 CGLIB）

如果坚持 "泛型只写一次、不允许子类再传 Class"，**解析动作放在工厂侧、用 Spring 的&#x20;**`ResolvableType`**，而不是基类构造器里裸调&#x20;**`getGenericSuperclass()`：



```
public abstract class AutoTypedHandler<T> implements MessageHandler {
    // 基类不解析泛型、不注册；只实现模板流程
    @Override
    public String type() { return type; }
    protected final String type;
    protected AutoTypedHandler(String type) { this.type = type; }
    // handle(...): 泛型转换由工厂拿到 payloadType 后通过受包级保护的方法注入，
    // 或直接在子类实现，按工程取舍
    protected abstract void onMessage(WebSocketSession s, T payload);
}

// 工厂构造器内集中解析
public MessageDispatcher(List<AutoTypedHandler<?>> all) {
    for (AutoTypedHandler<?> handler : all) {
        // getUserClass 剥掉 CGLIB 代理层；ResolvableType 按基类泛型签名解析，能穿透代理
        Class<?> userClass = ClassUtils.getUserClass(handler.getClass());
        Class<?> payloadType = ResolvableType.forClass(userClass)
                .as(AutoTypedHandler.class)
                .getGeneric(0)
                .resolve();
        if (payloadType == null || payloadType == Object.class) {
            // 泛型不可解析/未声明具体类型 → fail-fast，不静默降级
            throw new IllegalStateException(
                    handler.getClass().getName() + " 必须声明具体的泛型 payload 类型");
        }
        register(handler.type(), handler, payloadType);
    }
}
```

要点：



* `ResolvableType` 是 Spring 专门为泛型解析设计的工具，对 CGLIB 子类、多层泛型继承的处理远完备于手写 `getGenericSuperclass()` + while 上溯；

* `ClassUtils.getUserClass()` 先剥代理类是 Spring 官方惯例；

* **解析时机在工厂装配期、解析对象是别人**，策略类自身不反射、不自注册，绕开坑 1 与坑 2。

选型建议：**优先显式传 Class**（最简单、零反射、编译期挡错）；策略数量大、基类层级深、确实要消除重复时，才用工厂侧 `ResolvableType`。

## 六、边界与变体



| 情况                             | 处理                                                                                     |
| ------------------------------ | -------------------------------------------------------------------------------------- |
| key 是枚举码（如 `enum.getStatus()`） | 用枚举常量做 key，禁止字符串拼接（原型中 `status + desc` 拼 key 是反模式）                                     |
| 想直接按数据 Class 路由（无字符串 key）      | 注册表用 `Map<Class<?>, Handler>`，工厂侧 `ResolvableType` 解析出的 Class 即键                       |
| 一个策略处理多个 key                   | 接口返回 `Set<String> types()`，工厂逐个登记并校验重复                                                 |
| 策略依赖其他 Bean                    | 一律构造器注入、字段 final；避免与工厂形成循环依赖（把会话管理与分发器拆开就是为打断 "管理器→处理器→管理器" 环）                      |
| 策略在插件 jar 里，Spring 扫描不到        | 走 SPI + 插件 Registry（见 ClassLoader 委派与 PluginRegistry），**不允许退回静态 register** |
| 策略内部需要事务                       | 注解放具体业务方法上；同时这正是会触发 CGLIB 的点，所以泛型更不能在构造器自解析                                            |
| 调用方拿不到策略时该怎么办                  | 明确语义：要么抛异常 fail-fast，要么返回 Optional 由调用方显式处理；禁止返回 null 让调用方 NPE                         |

## 七、错误案例



| 错误操作                                  | 实际后果                           | 正确做法                                               |
| ------------------------------------- | ------------------------------ | -------------------------------------------------- |
| 父类无参构造器 `getGenericSuperclass()` 解析泛型 | CGLIB 代理 Bean 上解析失败，启动期 / 运行期崩 | 子类显式传 Class；或工厂侧 `ResolvableType` + `getUserClass` |
| 构造器里调静态 `Factory.register(key, this)` | this 逃逸、全局静态状态、测试污染、代理后注册失效对象  | 工厂 Bean 注入 `List<策略>` 集中注册，无静态表                    |
| 泛型解析失败 catch 后返回 `Object.class`       | 类型校验失效，问题推迟到业务数据进来             | 解析不出直接启动失败                                         |
| `map.put(key, handler)` 注册            | 后注册静默覆盖，先做的功能整体失效              | `putIfAbsent`，重复即启动失败并报出两个类名                       |
| 策略类忘加 `@Component`                    | 永不注册且无报错，功能静默缺失                | 靠 Spring 收集 + 启动日志核对已注册 key 集合；测试中断言 key 数量        |
| 策略里字段 `@Autowired`                    | 隐式依赖、不可 final、脱离容器不可用          | 构造器注入，依赖声明 final                                   |
| key 用 `status + desc` 字符串拼接           | 描述一改路由全断，key 不可控               | 枚举常量 / 集中常量登记                                      |

## 八、检查清单



* [ ] 策略接口声明 key 与统一入口；泛型抽象模板只收敛公共流程，不做注册

* [ ] 所有具体策略是 Spring Bean（`@Component`），依赖全部构造器注入、字段 final

* [ ] 泛型 Class 由子类构造显式传入，或由工厂侧 `ResolvableType`（配 `ClassUtils.getUserClass`）解析；基类构造器中没有 `getGenericSuperclass()` 自解析

* [ ] 工厂是 Spring Bean，构造器注入 `List<策略接口>` 自动收集，注册表是实例字段而非 static

* [ ] key 缺失、key 重复、泛型不可解析一律启动失败（fail-fast），无静默覆盖与降级

* [ ] 启动日志打印已注册 key 集合，可与预期清单核对

* [ ] 新增一个策略分支时，工厂与调用方代码零改动