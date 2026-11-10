# X Creator Studio 中文适配

为 X iOS 的 Creator Studio（创作者工作室）菜单提供简体中文文案。仅在检测到页面标题、原创内容奖励、创作者学院和工具等特征后处理可见 UIKit 标签和按钮；不会改变资格状态或解锁收益功能。

## 下载和安装

在 Actions 的 Build 页面下载成功任务的 XCreatorStudioZH 压缩包，解压取得 XCreatorStudioZH.dylib。使用支持注入动态库的 IPA 签名工具（例如你现有的签名工具）将其注入已解密的 X IPA，重新签名后安装。单独安装 dylib 不会生效。默认仅在原始 bundle ID com.atebits.Tweetie2 下启用；克隆包修改 bundle ID 需要相应修改源码。

插件不依赖 MobileSubstrate，不包含 X IPA、Apple 凭据或解密材料。原始 IPA 参考任务：https://github.com/zwthys-cyber/ipa-decrypt-lab/actions/runs/42738640961 。该任务的加密 IPA 不能直接作为普通 IPA 注入。

## 验证范围

GitHub Actions 编译 arm64 / arm64e，检查 Mach-O 架构并验证临时签名。CI 通过只证明编译和静态结构通过，不证明你的 X 版本页面已实际中文化。尚未用真实 IPA 或设备验证；若页面使用非 UIKit 绘制或文案改变，可能无法匹配。请安装后打开截图中的页面确认效果，再报告仍显示英文的区域。

## 开发约束

所有编译、运行、自动测试和产物验证仅允许在 GitHub 托管 Actions runner 上进行。当前服务器仅允许编辑文件和调用 GitHub API，不允许运行项目、安装编译依赖或测试。源码直接通过 GitHub API 维护。公开产物仅含本项目插件。
