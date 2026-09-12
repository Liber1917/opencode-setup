---
name: mineru-local
description: >
  本地文档解析(MinerU local)。选装 INSTALL_MINERU=1 部署。PDF/图片/DOCX/PPTX/XLSX → Markdown,
  本地处理零外发(隐私文档首选)。触发:解析 PDF/文档提取/OCR/表格公式识别/转 Markdown。
  用法: mineru -p <文件> -o <输出目录> [-b pipeline|vlm-engine];批量: -p 传目录。
  模型首次运行自动从 modelscope 下载(数 GB)。20 页内快速任务可用 Flash MCP 替代(见正文)。
---

# 本地文档解析(MinerU local)

## 何时用

- **隐私文档**:本地处理零外发——这是与 Flash MCP(云端)的本质区别
- **大批量/超 20 页文档**:Flash 免费档限额单文件 20 页/10MB,本地无限制
- 输入:PDF、图片(png/jpg/webp/tiff)、DOCX、PPTX、XLSX;输出 Markdown + JSON(公式→LaTeX,表格→HTML)

## 使用方法

```bash
# 单文件(核心用法)
mineru -p 文档.pdf -o ./output

# 目录批量(自动扫描全部支持格式,重名自动去重并告警)
mineru -p ./my_docs/ -o ./output

# 指定语言提示(提升 OCR 精度,默认 ch)
mineru -p 文档.pdf -o ./output -l ch
```

## 后端选择(-b)

不带 `-b` 时默认 `hybrid-engine`(需 GPU);**纯 CPU 环境必须显式指定 `-b pipeline`**。

| 后端 | 特点 | 硬件 |
|---|---|---|
| `pipeline` | OCR 级联多模型,零幻觉,结果可靠 | 纯 CPU 可跑 |
| `vlm-engine` | 视觉语言模型端到端,精度最高 | 需 GPU |
| `hybrid-engine` | pipeline+VLM 混合(默认) | 需 GPU |

```bash
mineru -p 扫描件.pdf -o ./output -b pipeline     # 纯 CPU / 零幻觉优先
mineru -p 复杂排版.pdf -o ./output -b vlm-engine  # 有 GPU,精度优先
```

## 输出读法

```
<输出目录>/<文档名>/<method>/            # method = auto/txt/ocr
  ├── <文档名>.md      # 主产物:Markdown(图片引用 images/ 相对路径)
  ├── <文档名>.json    # 结构化 JSON(布局/阅读顺序)
  └── images/          # 提取的图片
```

读 `.md` 即得全文;表格在 `.md` 中为 HTML,公式为 LaTeX。

## 注意事项

- 模型数 GB,**首次运行自动从 modelscope 下载**(`MINERU_MODEL_SOURCE=modelscope` 已由 setup 写入 ~/.bashrc,新终端生效)
- 大文件解析为分钟级耗时,批量任务给足超时;磁盘建议 20GB+、内存 16GB+
- 20 页内轻量任务可改用 Flash MCP(云端免 key,文档传 mineru.net 处理)——**隐私文档勿用 Flash,用本 CLI**
