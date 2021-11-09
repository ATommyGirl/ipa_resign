# ipa_resign
## Parameter
```sh
-p #可选，描述文件的路径
-v #可选，重签名的目标版本号
-b #可选，重签名的目标 Build 号
```

## Use
```sh
sh ios_app_signature_tool.sh old_ipa_1.0.3.ipa
```

or

```sh
sh ios_app_signature_tool.sh -p ./ -v '1.0.4' -b '20' old_ipa_1.0.3.ipa
```
