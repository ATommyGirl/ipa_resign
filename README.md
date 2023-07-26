# ipa_resign
## Parameter
```sh
-p #描述文件的路径
-s #可选，描述文件所在的文件夹，如果 App 同时有 Extension 需要重签名，建议使用这种方式
-v #可选，重签名的目标版本号
-b #可选，重签名的目标 Build 号
```

## Use
```sh
sh ios_app_signature_tool.sh -p /Users/tommy/Desktop/PP.mobileprovision old_ipa_1.0.3.ipa
```

or

```sh
sh ios_app_signature_tool.sh -p /Users/tommy/Desktop/PP.mobileprovision -v '1.0.4' -b '20' old_ipa_1.0.3.ipa
```

or

```sh
sh ios_app_signature_tool.sh -s /Users/tommy/Desktop/your-PP-folder -v '1.0.4' -b '20' old_ipa_1.0.3.ipa
```

##Error

我的 Mac 系统更新以后，使用 Base64 命令会报错，修改了一下参数
```sh
base64: invalid argument -Dd
Usage:	base64 [-hDd] [-b num] [-i in_file] [-o out_file]
  -h, --help     display this message
  -Dd, --decode   decodes input
  -b, --break    break encoded string into num character lines
  -i, --input    input file (default: "-" for stdin)
  -o, --output   output file (default: "-" for stdout)
unable to load certificate
```
-Dd 改为了 --decode

