# CANN LLM so 文件说明

此目录应包含以下预编译库：

- `libllm_core.so` - CANN LLM 核心推理库
- `libhiai_llm_engine.so` - HIAI LLM 引擎库
- `libc++_shared.so` (可选) - C++ 运行时库

## 获取方式

这些文件需要从以下渠道获取：

1. **内部渠道**：联系项目维护者获取预编译 so 文件
2. **自行编译**：从源码编译 libllm_core.so

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

## 注意

- so 文件未包含在 Git 仓库中（体积过大）
- 编译需要这些文件，否则 cann-local 功能不可用
- 其他功能不受影响
