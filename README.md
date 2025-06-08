# 我只是想拿zig试一试写一个maimai排队bot

这也太麻烦了，全部都要自己封装

无敌了

目前遇到的坑

* 还不知道如何分系统导入clib
* 时间戳处理只写了UTC，还没写LocalTime
* print的格式化根本调试不了，报错完全看不明白
* 社区环境基本没有什么封装好的库，全要自己造
* 它甚至连shared_ptr都没有
* 多线程queue也没有

TODO 核心方面:

* 增加更多OneBot API
* 优化错误处理，现在一个出错整个程序爆炸
* 检查内存泄漏
* 优化性能

TODO 功能方面:

* 增加管理指令，群绑定，城市添加
* 上传时间显示可以更直观
* （也许）增加个人关注机厅的功能
* （也许）把文字输出改成图片

## refrence

<https://github.com/Aandreba/zigrc>
<https://github.com/erik-dunteman/chanz>
<https://github.com/JakubSzark/zig-string>
<https://github.com/karlseguin/websocket.zig>
