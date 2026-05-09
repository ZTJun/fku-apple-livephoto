# fku-apple-livephoto
一个可以将视频和文件转换成 Apple Live Photo 的简单 Swift 脚本 / A simple swift script aims to converting video and photo to Apple Live Photo

# 用法 / Uasge
## 中文
1. 下载 `fku-livephoto.swift`，保存至指定的文件夹
2. 在文件夹目录打开终端，输入 `chmod +x ./fku-livephoto.swift`
3. 假设 `input.heic` 和 `input.mov` 分别是你的两个输入文件，`output` 是你设定的文件输出名前缀，`UUID` 为你给生成的 Live Photo 指定的 UUID ，通常为全大写 `UUID4`，执行 `./fucku-livepoto.swift input.heic output UUID` 可以得到 `output.heic` 和 `output.mov` 两个修改过的文件
4. 打开 `照片.app` ，键盘输入 `Shift+Command+I` 打开导入界面，选择 `output.heic` 和 `output.mov` 两个修改过的文件即可

## English
1. Download `fku-livephoto.swift` and save it to your desired folder.
2. Open Terminal in that directory and enter the following command: `chmod +x ./fku-livephoto.swift`
3. Run the script using your input files. Assuming `input.heic` and `input.mov` are your source files and `output` is your chosen filename's prefix, and `UUID` is the unique ID you assign to the Live Photo, usually in all-caps UUID4 format, execute: `./fucku-livepoto.swift input.heic output UUID`. This will generate two modified files: output.heic and output.mov.
4. Open the `Photos app` and press `Shift + Command + I` to open the import interface. Select both `output.heic` and `output.mov` to import them as a Live Photo.

# 已知问题 / Known Issue
**不可以保留相机制造厂独特的私有数据块和少量和原始 [EXIF] 数据块**，已经可能用特殊方法保留原始 Metadata，如有特别需求可以搭配 `ExifTool` 查漏补缺
**Camera manufacturer-specific proprietary data blocks and certain original [EXIF] segments cannot be preserved.** While it is possible to retain original metadata through specialized methods, you can use `ExifTool` to supplement or fill in any missing information if you have specific requirements.
