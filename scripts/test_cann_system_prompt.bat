@echo off
echo ==========================================
echo CANN Local System Prompt Test
echo ==========================================
echo.
echo 测试问题：
echo.
echo 1. 角色设定测试
echo    Q: 你是谁？
echo    期望: 提到 ClawdBot, HarmonyOS
echo.
echo 2. 回复风格测试
echo    Q: 请详细介绍一下你自己
echo    期望: 1-2句话极简回复
echo.
echo 3. 记忆系统测试
echo    Q: 你能记住什么信息？
echo    期望: 提到个人信息、偏好、指令
echo.
echo 4. 平台信息测试
echo    Q: 你运行在什么平台上？
echo    期望: HarmonyOS, 本地推理
echo.
echo 5. 多轮对话+记忆测试
echo    第一轮: 我叫小明，记住我的名字
echo    第二轮: 我叫什么？
echo    期望: 回答"小明"
echo.
echo ==========================================
echo 查看日志命令：
echo hdc shell "hilog -x" ^| findstr /C:"Token Output" /C:"ModelInfer" /C:"LoadModel"
echo ==========================================
