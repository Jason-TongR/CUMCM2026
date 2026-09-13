# 本机 VS Code 编译运行说明

## 前置条件
- 已安装 [TeX Live](https://tug.org/texlive/)（本机为 2025 版，含 `xelatex`、`latexmk`）。
- 已安装 VS Code 扩展 `james-yu.latex-workshop`（LaTeX Workshop）。

## 打开与编译
1. 在 VS Code 中“文件 → 打开文件夹”，选择本 `Latex模板` 文件夹。
2. 双击打开 `2026_new_main.tex`。
3. 按 `Ctrl+S` 保存即可自动编译；也可按 `Ctrl+Alt+B` 手动“Build LaTeX project”。
4. 编译结果 `2026_new_main.pdf` 会出现在同目录，并自动在右侧标签页预览。

## 为什么配置了 XeLaTeX
模板的类文件 `cumcmthesis.cls` 强制要求 `xelatex`（它检测不到 `xelatex` 会直接报错）。
`.vscode/settings.json` 已经把默认构建引擎改成 xelatex，`% !TeX program = xelatex` 魔法注释也会生效。

## 常见问题
- 报错 “You must use the `xelatex' driver”：说明编译引擎仍被设成了 pdflatex，改回 xelatex 即可。
- 中文乱码/字体缺失：本机 Windows 用 XeLaTeX 没问题；若是 Overleaf，请改用 XeLaTeX 并替换 SimSun/楷体 字体（见上一版说明）。
