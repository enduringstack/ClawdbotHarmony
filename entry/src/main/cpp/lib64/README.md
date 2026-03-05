# CANN LLM so 文件说明

此目录应包含以下预编译库：

- `libllm_core.so` - CANN LLM 核心推理库
- `libhiai_llm_engine.so` - HIAI LLM 引擎库
- `libc++_shared.so` (可选) - C++ 运行时库

## 获取方式

### 方式 1：从源码编译（推荐）

源码仓库：https://codehub-y.huawei.com/x00897182/cann_llm_deploy/files

```bash
# 克隆源码
git clone ssh://git@szv-y.codehub.huawei.com:2222/x00897182/cann_llm_deploy.git

# 切换到 external-release 分支（外网版本）
git checkout external-release

# 在 DevEco Studio 中编译
# 生成的 so 文件在：entry/build/default/intermediates/cmake/default/obj/arm64-v8a/

# 复制到本项目
cp build/output/libllm_core.so path/to/ClawdbotHarmony/entry/src/main/cpp/lib64/
cp build/output/libhiai_llm_engine.so path/to/ClawdbotHarmony/entry/src/main/cpp/lib64/
```

### 方式 2：从预编译包获取

联系项目维护者获取预编译 so 文件。

## 放置位置

将 so 文件放置在当前目录 (`entry/src/main/cpp/lib64/`) 下。

## 验证

编译项目后，检查日志中是否有：
```
CANN LLM libraries found, enabling cann_llm module
```

如果没有 so 文件，编译时会显示：
```
CANN LLM libraries not found, cann_llm module will be disabled
```

## 注意事项

- so 文件未包含在 Git 仓库中（体积过大）
- 编译需要这些文件才能启用 cann-local 功能
- 其他功能不受影响
- TypeScript 层面的模块导入在编译时检查，没有 so 文件会报错
