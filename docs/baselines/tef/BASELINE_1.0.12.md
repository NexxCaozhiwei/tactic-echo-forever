# TEF 1.0.12

仅增加排队证据：独立512条queueDiagnostics及queueEvicted，经标量白名单在reload后保留。记录公开事件GUID、当前/原始/下一次身份、请求号、回执号、会话、代次、索引/次数、时钟、配置/客户端/有效提前量和请求时剩余读条时间。明确记录窗口失败分类及当前成功时缺少下一次身份。QUEUE_FAILURE_EVENT与QUEUE_SUCCESS_BEFORE_CURRENT_SUCCESS用于区分旧REJECTED标签。TOKEN_PUBLISHED仅表示插件输出，不证明TEK输入。派发及回执资格不变。回归验证事件关联、Secret过滤、容量上限和reload保留。
