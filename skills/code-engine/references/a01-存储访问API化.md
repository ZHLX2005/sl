***

name: a01 - 存储访问 API 化

description: 所有存储设施禁止全局直达，必须经收敛的 API 出口访问。前端（含浏览器插件 chrome.storage、localStorage、IndexedDB）和后端（数据库 SQL、Redis、配置存储）都适用；后端 SQL 只允许存在于数据访问层，禁止 Service/Controller/ 工具类 / 跨模块直查造成 SQL 层相互腐蚀。涉及 “存储能不能直接调 / SQL 写在哪 / 查别人的表 /key 散落” 时读取。



***

# a01 存储访问 API 化 —— 禁止全局存储直达

> 通用代码设计规范，与语言、框架无关。

## 规范命题

**存储天然是全局的，但 “全局可达” 不代表 “全局可直接访问”。**

浏览器把 `chrome.storage`、`localStorage` 挂成全局对象，任何 JS 上下文一行代码就能读写；后端框架让你在任意 Bean 里注入 `JdbcTemplate` / `RedisTemplate` / 任意 Mapper。这种 “在哪都能存” 的便利是结构腐蚀的起点：



* **key 散落**：同一个数据在 N 个文件里用字符串 key 读写，拼错不报错；

* **规则不一致**：序列化格式、TTL、默认值、异常处理各写各的；

* **横切规则漏接**：租户条件、数据权限、逻辑删除、审计字段靠业务 “记得带”，新写的查询忘了带就是数据穿透；

* **不可替换、不可测试**：换存储实现（localStorage → chrome.storage、MySQL → PG）或写单测时，要全项目搜改。

**唯一允许的形态：存储 API 收敛到一个出口模块，业务代码只依赖语义化的 API，不碰底层存储对象。**

## 前端（含浏览器插件）

### 反例：全局对象任意位置直接调



```
// login.ts
await chrome.storage.local.set({ token: resp.token });

// 某个 content script 里
const bag = await chrome.storage.local.get('orderCfg');
const cfg = bag.orderCfg ? JSON.parse(bag.orderCfg) : null;

// 另一个文件里，key 拼错成 orderConfig，静默拿到 undefined
const old = await chrome.storage.local.get('orderConfig');
```

`chrome.storage` 是典型的 “全局插件对象，支持在任意地方实现存储访问”——**本规范明确禁止这样用**。`localStorage`、`indexedDB`、`window.__INITIAL_STATE__` 同理。

### 正例：三层结构，底层全局对象只出现一次



```
// 1) key 唯一登记表
export const STORE_KEYS = {
  session: 'app.session',
  settings: 'app.settings',
} as const;

// 2) StorageClient：chrome.storage 全局对象在整个工程里只允许出现在这一层
export interface StorageClient {
  get<T>(key: string): Promise<T | null>;
  set<T>(key: string, value: T): Promise<void>;
  remove(key: string): Promise<void>;
}

export class ChromeStorageClient implements StorageClient {
  constructor(private readonly area: 'local' | 'session' = 'local') {}

  async get<T>(key: string): Promise<T | null> {
    const bag = await chrome.storage[this.area].get(key);
    const raw = bag[key];
    if (raw === undefined) return null;
    try {
      return JSON.parse(raw) as T;          // 序列化规则统一在这
    } catch (e) {
      throw new Error(`存储数据损坏，key=${key}`, { cause: e });
    }
  }

  async set<T>(key: string, value: T): Promise<void> {
    await chrome.storage[this.area].set({ [key]: JSON.stringify(value) });
  }

  async remove(key: string): Promise<void> {
    await chrome.storage[this.area].remove(key);
  }
}

// 测试或非插件环境可平替：new MemoryStorageClient()，业务代码无感

// 3) 面向业务的语义化存储 API
export class SessionStore {
  constructor(private readonly storage: StorageClient) {}
  load(): Promise<Session | null> { return this.storage.get<Session>(STORE_KEYS.session); }
  save(session: Session): Promise<void> { return this.storage.set(STORE_KEYS.session, session); }
  clear(): Promise<void> { return this.storage.remove(STORE_KEYS.session); }
}
```

业务代码只注入 `SessionStore`，调 `load/save/clear`。以后要加过期时间、版本号、变更埋点、加密，只改出口层一处。

> content script 与 service worker 存储模型不同（MV3 下 content script 拿不到部分扩展 API），通过让两侧持有不同 
>
> `StorageClient`
>
>  实现解决，而不是让业务代码判断上下文。

## 后端：禁止 SQL 语句层相互腐蚀

### “SQL 腐蚀” 长什么样



```
// 1) Service/Controller 里直接拼 SQL —— 禁止
@Autowired JdbcTemplate jdbc;
jdbc.queryForList("select * from t_order where user_id = " + uid);   // 注入面 + 绕过一切横切规则

// 2) 工具类/定时任务里 @Autowired RedisTemplate 直接拼 key —— 禁止
redisTemplate.opsForValue().set("order:" + id, order, 1, TimeUnit.HOURS);

// 3) A 模块的 Service 直接注入 B 模块的 Mapper 查 B 的表 —— 禁止
@Autowired OrderMapper orderMapper;   // 在 UserService 里
```

第 1 条 SQL 出现时只是 “省事”，第 N 条出现后：加租户隔离要全项目搜 SQL、改表名要全项目搜表名、别人改了表结构你编译不报错、运行期才炸。这就是**层与层之间的相互腐蚀**—— 数据访问逻辑渗进了业务层，业务模块之间又通过库表直接耦合。

### 正例：SQL 唯一出口 + 跨域走 API + 横切走拦截器



```
// 1) SQL 只允许存在于 Mapper/Repository 层（注解、XML、链式包装器都算这一层）
public interface OrderMapper extends BaseMapper<Order> { }

// 2) 本域 Service 只调本域 Mapper；参数化条件，不拼字符串
@Service
@RequiredArgsConstructor
public class OrderQueryService {

    private final OrderMapper orderMapper;

    public List<Order> listByUser(Long userId) {
        return orderMapper.selectList(
                Wrappers.<Order>lambdaQuery().eq(Order::getUserId, userId));
    }
}

// 3) 其他模块/服务需要订单数据 → 注入对方的 Service API，绝不直接碰 OrderMapper
@Service
@RequiredArgsConstructor
public class UserDashboardService {
    private final OrderQueryService orderQueryService;   // 跨域唯一通道
}
```

**横切规则不写进每条 SQL，而是在出口层统一改写**：



| 横切能力                      | 统一落点                                                            | 为什么不能靠业务                           |
| ------------------------- | --------------------------------------------------------------- | ---------------------------------- |
| 多租户 `tenant_id` 条件 / 数据权限 | SQL 改写拦截器（JSqlParser，插件链最前）                                     | 新写的查询忘了带条件 = 租户数据穿透，应用层校验必然漏       |
| 逻辑删除、防全表更新 / 删除           | MP 拦截器（BlockAttack）                                             | 业务不会主动写 `deleted = 0`，全表更新一旦发生无法回滚 |
| 审计字段（创建 / 更新人、时间）         | 自动填充 Handler                                                    | 靠人填必然有漏网数据                         |
| Redis key 前缀 / TTL / 序列化  | 收敛的 Cache/Repository API（如 `AbstractRedisStringCache<IN, OUT>`） | key 拼错、TTL 缺失、序列化器不一致都是运行期事故       |

拦截器 / 出口层统一处理的哲学：**“应用层校验会漏，出口层改写不会。”** 命中规则但上下文缺失（如租户未设置）时 fail-fast 抛错，也不放行全表查询。

## 判定三问（代码评审时逐条问）



1. **全局存储对象（chrome.storage/localStorage / JdbcTemplate / RedisTemplate / 原生连接）在封装层之外还有出现吗？** 有 → 不合规。

2. **这段 SQL / 查询语句位于哪一层？** 不在 Mapper/Repository 层 → 不合规；查的是别的域的表 → 走对方 Service API。

3. **换掉存储实现或改一个 key / 表名，要动几个文件？** 答案超过 1 个（出口层） → 存储没有真正收敛。

## 错误案例



| 错误操作                                       | 实际后果                                   | 正确做法                                          |
| ------------------------------------------ | -------------------------------------- | --------------------------------------------- |
| 业务各处直接 `chrome.storage.local.get/set`      | key 拼错静默返回 undefined；序列化格式不统一；改存储要全项目搜 | 全局对象只在 `StorageClient` 实现层出现，业务走语义化 Store API |
| Service 里 `jdbc.queryForList("... " + 参数)` | SQL 注入；绕过租户 / 逻辑删除 / 审计拦截；换库方言不兼容      | SQL 收敛到 Mapper，条件参数化，横切规则交拦截器                 |
| A 模块注入 B 模块的 Mapper 直查 B 的表                | 表结构变更跨模块爆炸；域边界失效；绕过 B 的数据权限            | 注入 B 模块的 Service/Query API                    |
| 各处 `redisTemplate.set("biz:"+id, ...)`     | key 冲突 / 拼错、TTL 缺失、序列化不一致              | 经统一 Cache API，key 常量登记，TTL / 序列化集中配置          |
| 租户条件靠业务在每个查询手写 `.eq(tenantId)`             | 新查询漏带条件，租户数据穿透                         | SQL 改写拦截器兜底，应用层只做二次校验                         |

## 检查清单



* [ ] 全局存储对象在整个工程中只出现在唯一的封装层文件内

* [ ] key 全部集中登记，无散落字符串；序列化 / 默认值 / 异常处理在出口层统一

* [ ] SQL 只存在于 Mapper/Repository 层；Service/Controller/Util/ 定时任务中无 SQL 字符串与原生查询

* [ ] 无跨模块直查他域表；跨域数据获取一律走对方 Service API

* [ ] 租户 / 权限 / 逻辑删除 / 审计等横切规则在拦截器或出口层统一生效

* [ ] 存储实现可平替（内存 / Mock），业务层无感知；单测不需要真实存储环境