#!/bin/bash

# 参考：
# 临时文件使用说明：https://www.ruanyifeng.com/blog/2019/12/mktemp.html
# Checking Distribution Entitlements：https://developer.apple.com/library/archive/qa/qa1798/_index.html
# iOS的ipa包重签名：https://blog.devlxx.com/2016/04/23/iOS%E7%9A%84ipa%E5%8C%85%E9%87%8D%E7%AD%BE%E5%90%8D/

set -eu

# 从 mobileprovision 中提取 plist
extract_mobileprovision_plist() {
    security cms -D -i "$1"
}


# 从 mobileprovision 中提取 指定字段内容
extract_field_content() {
    local filename="$1"
    local path="$2"
    extract_mobileprovision_plist "${filename}" | plutil -extract "${path}" xml1 -o - -- -
}


# 从 mobileprovision 中提取 指定字段值
extract_field_value() {
    local filename="$1"
    local path="$2"
    local val=$(extract_field_content "${filename}" "${path}" | plutil -p -- -)
    eval "echo ${val}"
}

# 从 mobileprovision 中提取 Entitlements，格式为 plist，内容在签名时使用
extract_entitlements() {
    local filename="$1"
    local entitlements_val=$(extract_field_content "${filename}" Entitlements)
    echo "${entitlements_val}"
}

# 从描述文件中获取 是否为 In-House 发布文件
extract_is_inhouse_profile() {
    local ret=$(extract_field_value "$1" ProvisionsAllDevices 2>/dev/null || :)
    echo "${ret}"
}

# 从描述文件中获取 BundleID
extract_bundle_id() {
    extract_field_value "$1" 'Entitlements.application-identifier'
}

# 从描述文件中获取 TeamName
extract_team_name() {
    extract_field_value "$1" 'TeamName'
}


# 时间戳
gen_timestamp() {
    # 以当前时间作为时间戳
    local timestamp_cmd='date +%Y%m%d%H%M%S'
    local timestamp=$(${timestamp_cmd})
    echo "${timestamp}"
}

# 获取 ipa 解压缩目录
extract_ipa_folder() {
    local timestamp=$(gen_timestamp)
    local IPA_FILE="$1"
    local folder_name=/tmp/ipa_signer/$(basename "${IPA_FILE}" .ipa)_${timestamp}
    mkdir -p '/tmp/ipa_signer' || :
    echo "${folder_name}"
}

# 删除签名
remove_code_signature() {
    local code_signature_path="$1/_CodeSignature"
    if [[ -d "${code_signature_path}" ]]; then
        rm -rf "${code_signature_path}"
    fi
}

# 按照 BundleID 查找匹配的描述文件
search_mobileprovision() {
    # 如果指定了描述文件目录
    if [[ -d "${MOBILEPROVISION_PATH}" ]]; then
        # 遍历指定目录下所有描述文件
        local mobileprovision_files=$(find "${MOBILEPROVISION_PATH}" -type f -name '*.mobileprovision')
        old_ifs=${IFS}
        IFS=$'\n'
        mobileprovision_files=(${mobileprovision_files})
        IFS=${old_ifs}
        for provision_file in "${mobileprovision_files[@]}"; do
            # 获取描述文件的 BundleID
            local bundle_id=$(extract_bundle_id "${provision_file}")
            local is_inhouse_profile=$(extract_is_inhouse_profile "${provision_file}")
            # 判断是否是 In-House 发布证书
            if [[ "${is_inhouse_profile}" != "1" ]]; then
                continue
            fi
            # 判断是否与传入的 BundleID 匹配
            if [[ "${bundle_id}" == "$1" ]]; then
                echo "${provision_file}"
                break
            fi
        done
    fi
}


# 指定版本 CFBundleShortVersionString
set_short_version() {
    local info_plist="$1"
    local short_ver="$2"
    plutil -replace 'CFBundleShortVersionString' -string "$short_ver" "$info_plist"
}

# 指定 Build CFBundleVersion
set_build_version() {
    local info_plist="$1"
    local build_ver="$2"
    plutil -replace 'CFBundleVersion' -string "$build_ver" "$info_plist"
}


# 代码签名
sign_code() {
    local sign_path="$1"
    # 删除原签名
    remove_code_signature "${sign_path}"
    # 获取旧的描述文件
    local old_profile="${sign_path}/embedded.mobileprovision"
    # 获取原来的 BundleID
    local bundle_id=$(extract_bundle_id "${old_profile}")
    # 根据 BundleID 在指定目录中查找新的描述文件
    local new_profile=$(search_mobileprovision "${bundle_id}")
    # 如果找到了新的描述文件则替换旧的
    if [[ -n "${new_profile}" ]]; then
        cp "${new_profile}" "${old_profile}"
    else
        # 如果没找到新的描述文件则用旧的
        new_profile="${old_profile}"
    fi
    # echo -e "Use \"\033[94;1m${new_profile}\033[0m\" to sign..."
    # 从描述文件中提取 Entitlements
    entitlements_content=$(extract_entitlements "${new_profile}")
    # 临时文件
    local tmp_entitlements_file=$(mktemp)
    # 生成 entitlements 文件
    echo "${entitlements_content}" > "${tmp_entitlements_file}"
    # 获取 TeamName
    local team_name=$(extract_team_name "${new_profile}")
    local sign_cert="iPhone Distribution: ${team_name}"
    echo
    echo -e "\033[97;1m[Signing Information]\033[0m"
    echo -e "    Bundle ID            : \033[93;1m${bundle_id}\033[0m"
    echo -e "    Provisioning Profile : \033[93;1m${new_profile}\033[0m"
    echo -e "    Signing Certificate  : \033[93;1m${sign_cert}\033[0m"
    echo -e "    entitlements.plist   : ${tmp_entitlements_file}"
    # 签名
    local sign_cmd_line='codesign -f -s '"\"${sign_cert}\""' --entitlements '"'${tmp_entitlements_file}'"' '"'${sign_path}'"
    echo    "    Command line:"
    echo    "-----------------------------------------------------------------------------------------------"
    echo -e "\033[92m${sign_cmd_line}\033[0m"
    echo -e "-----------------------------------------------------------------------------------------------"

    # codesign -f -s "${sign_cert}" --entitlements "${tmp_entitlements_file}" "${sign_path}"
    local result=$(eval "${sign_cmd_line}" 2>&1)
    echo -e "    Execution result     : \033[94;1m${result}\033[0m"

    # echo "======"
    rm "${tmp_entitlements_file}"
}

# 参数个数
# echo $#

# 初始化变量
# ipa 文件
IPA_FILE=''
# 指定的 Mobile Provision Profile 目录
MOBILEPROVISION_PATH=''
# 版本号
IPA_SHORT_VERSION=''
# Build 号
IPA_BUILD_VERSION=''

# 处理脚本参数
# -p Mobile Provision Profile 所在目录
# -v 版本
# -b Build 信息
while getopts ":p:v:b:" opt
do
    case "$opt" in
        'p')
            MOBILEPROVISION_PATH="$OPTARG"
            ;;
        'v')
            IPA_SHORT_VERSION="$OPTARG"
            ;;
        'b')
            IPA_BUILD_VERSION="$OPTARG"
            ;;
        ?)
            echo "Unknown arguments."
            exit 1
            ;;
    esac
done

# 删除已解析的参数
shift $((OPTIND-1))

# ipa 文件
IPA_FILE=${1-''}

# 没有指定 ipa 文件
if [[ -z "${IPA_FILE}" ]]; then
    cat << EOF

Usage:
  ios_sign_tool [options] <ipa_file>

Options:
  -p <provisioning_profiles_folder>  Specify the directory containing the mobile provision profile.
  -v <version>                       Specify the short version string(CFBundleShortVersionString) of the ipa file.
  -b <build_version>                 Specify the build version string(CFBundleVersion) of the ipa file.

EOF
    exit
fi

# ipa 文件不存在
if [[ ! -f "${IPA_FILE}" ]]; then
    echo File not exists.
    exit
fi

# 获取解压缩目录
extract_path=$(extract_ipa_folder "${IPA_FILE}")
echo "Extracting \"${IPA_FILE}\"..."
echo "to \"${extract_path}/\"..."

# 解压缩
unzip -q "${IPA_FILE}" -d "${extract_path}"

# Payload 目录
payload_path="${extract_path}/Payload"
# App 目录
app_path="${payload_path}/"$(ls -C1 "${payload_path}" | head -n 1)



# 获取扩展所在目录
plugins_path="${app_path}/PlugIns"

# 如果存在扩展目录则处理
if [[ -d "${plugins_path}" ]]; then
    # 列出扩展
    plugins=$(find "${plugins_path}" -type d -name '*.appex')
    old_ifs=${IFS}
    IFS=$'\n'
    plugins=(${plugins})
    IFS=${old_ifs}
    # 遍历扩展，为每个扩展签名
    for plugin in "${plugins[@]}"; do
        echo
        echo "Signing extension \"${plugin}\"..."
        sign_code "${plugin}"
    done
fi


# 指定主程序版本
echo 'Specify the main app version:'

# 指定 Version
if [[ -n "${IPA_SHORT_VERSION}" ]]; then
    echo "  Version(CFBundleShortVersionString)=${IPA_SHORT_VERSION}"
    set_short_version "${app_path}/Info.plist" "${IPA_SHORT_VERSION}"
fi

# 指定 Build
if [[ -n "${IPA_BUILD_VERSION}" ]]; then
    echo "  Build(CFBundleVersion)=${IPA_BUILD_VERSION}"
    set_build_version "${app_path}/Info.plist" "${IPA_BUILD_VERSION}"
fi

# 为主程序签名
echo
echo "Signing application \"${app_path}\"..."
sign_code "${app_path}"

# 新 ipa 文件名
new_ipafile=$(dirname "${IPA_FILE}")/$(basename "${IPA_FILE}" .ipa)_sign_$(gen_timestamp).ipa

echo
echo "Packing \"${new_ipafile}\"..."

# 重签名后的 ipa 文件（临时）
resigned_ipa="${extract_path}/resigned.ipa"

# 进入工作目录，zip 命令只能在这个目录下工作，否则压缩包内会带上完整路径
pushd "${extract_path}" > /dev/null
zip -q -r "${resigned_ipa}" "Payload"
popd > /dev/null

# 由于 /tmp 目录作为工作目录，导致文件权限有些问题，所以不能使用 mv 命令
# 而是需要 cp 命令将签名后的文件复制到指定位置
cp "${resigned_ipa}" "${new_ipafile}"

# 删除临时文件，清理工作区
echo
echo "Clearing workspace..."
rm -rf '/tmp/ipa_signer'

# 完成
echo
echo 'Done.'
echo

# 打开签名后文件所在目录
open "$(dirname "${new_ipafile}")"
