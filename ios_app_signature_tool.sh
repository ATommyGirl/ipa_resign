#!/bin/bash

# 参考：
# 临时文件使用说明：https://www.ruanyifeng.com/blog/2019/12/mktemp.html
# Checking Distribution Entitlements：https://developer.apple.com/library/archive/qa/qa1798/_index.html
# iOS的ipa包重签名：https://blog.devlxx.com/2016/04/23/iOS%E7%9A%84ipa%E5%8C%85%E9%87%8D%E7%AD%BE%E5%90%8D/

set -euo pipefail

# 从 mobileprovision 中提取信息 =================================================

# 从 mobileprovision 中提取 plist
extract_mobileprovision_plist() {
    security cms -D -i "$1"
}


# 从 mobileprovision 中提取 指定字段内容
extract_field_content() {
    local filename="$1"
    local path="$2"
    local content
    content=$(extract_mobileprovision_plist "${filename}" | plutil -extract "${path}" xml1 -o - -- -)
    if [[ "0" -ne "$?" ]]; then
        content='""'
    fi
    echo "$content"
}


# 从 mobileprovision 中提取 指定字段值
extract_field_value() {
    local filename="$1"
    local path="$2"
    local val
    val=$(extract_field_content "${filename}" "${path}" | plutil -p -- -)
    eval "echo \"${val}\""
}

# 从 mobileprovision 中提取 Entitlements，格式为 plist，内容在签名时使用
extract_entitlements() {
    local filename="$1"
    local entitlements_val
    entitlements_val=$(extract_field_content "${filename}" Entitlements)
    echo "${entitlements_val}"
}

# 从描述文件中获取 是否为 In-House 发布文件
extract_is_inhouse_profile() {
    local ret
    ret=$(extract_field_value "$1" ProvisionsAllDevices 2>/dev/null || :)
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

# 处理 Info.plist 中的信息 ======================================================

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


# 代码运行中的临时变量 ===========================================================

# 时间戳
gen_timestamp() {
    # 以当前时间作为时间戳
    local timestamp_cmd='date +%Y%m%d%H%M%S'
    local timestamp
    timestamp=$(${timestamp_cmd})
    echo "${timestamp}"
}

# 获取 ipa 解压缩目录
extract_ipa_folder() {
    local timestamp
    timestamp=$(gen_timestamp)
    local IPA_FILE="$1"
    local folder_name
    folder_name="$TMP_WORKBENCH_ROOT"/$(basename "${IPA_FILE}" .ipa)_${timestamp}
    mkdir -p "$TMP_WORKBENCH_ROOT" || :
    echo "${folder_name}"
}

# 查找匹配的描述文件 =============================================================

# 按照 BundleID 查找匹配的描述文件
search_mobileprovision() {
    # 如果指定了描述文件目录
    if [[ -d "${MOBILEPROVISION_PATH}" ]]; then
        # echo MOBILEPROVISION_PATH "${MOBILEPROVISION_PATH}" | subl
        # 遍历指定目录下所有描述文件
        local mobileprovision_files
        mobileprovision_files=$(find "${MOBILEPROVISION_PATH}" -type f -name '*.mobileprovision')
        local old_ifs=${IFS}
        IFS=$'\n'
        local mobileprovision_files_array
        mobileprovision_files_array=(${mobileprovision_files})
        IFS=${old_ifs}
        # 判断是否找到了内容
        if [[ "0" -lt "${#mobileprovision_files_array[@]}" ]]; then
            # 遍历处理
            for provision_file in "${mobileprovision_files_array[@]}"; do
                # 获取描述文件的 BundleID
                local bundle_id
                bundle_id=$(extract_bundle_id "${provision_file}")
                local is_inhouse_profile
                is_inhouse_profile=$(extract_is_inhouse_profile "${provision_file}")
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

    fi
}

# 签名相关 ======================================================================

# 删除签名
remove_code_signature() {
    local code_signature_path="$1/_CodeSignature"
    if [[ -d "${code_signature_path}" ]]; then
        rm -rf "${code_signature_path}"
    fi
}


# 代码签名
sign_code() {
    local sign_path="$1"
    # 删除原签名
    remove_code_signature "${sign_path}"
    # 获取旧的描述文件
    local old_profile="${sign_path}/embedded.mobileprovision"
    # 获取原来的 BundleID
    local bundle_id
    bundle_id=$(extract_bundle_id "${old_profile}")
    # 根据 BundleID 在指定目录中查找新的描述文件
    local new_profile
    # 如果命令行中明确指定了描述文件
    if [[ -n "${MOBILEPROVISION_FILE}" ]]; then
        new_profile="${MOBILEPROVISION_FILE}"
        # 如果指定的描述文件不存在
        if [[ ! -f "${new_profile}" ]]; then
            echo Provision profile "${new_profile}" not exists.
            exit 1
        fi
    elif [[ -n "${MOBILEPROVISION_PATH}" ]]; then
        # 如果命令行中没有明确指定描述文件，但明确指定了描述文件的搜索位置
        # 则在指定路径中搜索
        new_profile=$(search_mobileprovision "${bundle_id}")
        # 判断搜索描述文件的结果
        if [[ ! -f "${new_profile}" ]]; then
            echo Provision profile not found.
            exit 1
        fi
    fi

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
    local tmp_entitlements_file
    tmp_entitlements_file=$(mktemp)
    # 生成 entitlements 文件
    echo "${entitlements_content}" > "${tmp_entitlements_file}"
    # 获取 TeamName
    # local team_name
    # team_name=$(extract_team_name "${new_profile}")
    # local sign_cert="iPhone Distribution: ${team_name}"
    local sign_cert=$CERTIFICATE_NAME_FOR_SIGNING
    echo
    echo -e "\033[97;1m[Signing Information]\033[0m"
    echo -e "    Bundle ID            : \033[93;1m${bundle_id}\033[0m"
    echo -e "    Provisioning Profile : \033[93;1m${new_profile}\033[0m"
    echo -e "    Signing Certificate  : \033[93;1m${sign_cert}\033[0m"
    echo -e "    entitlements.plist   : ${tmp_entitlements_file}"
    # 签名
    local sign_cmd_line='codesign -f -s '"\"${sign_cert}\""' \\\n         --entitlements '"'${tmp_entitlements_file}'"' \\\n         '"'${sign_path}'"
    echo    "    Command line:"
    echo    "-----------------------------------------------------------------------------------------------"
    echo -e "\033[92m${sign_cmd_line}\033[0m"
    # echo -e "${sign_cmd_line}"
    echo -e "-----------------------------------------------------------------------------------------------"

    # codesign -f -s "${sign_cert}" --entitlements "${tmp_entitlements_file}" "${sign_path}"
    # local result=$(eval "${sign_cmd_line}" 2>&1)
    local result
    result=$(codesign -f -s "${sign_cert}" --entitlements "${tmp_entitlements_file}" "${sign_path}" 2>&1)
    echo -e "    Execution result     : \033[94;1m${result}\033[0m"

    # echo "======"
    rm "${tmp_entitlements_file}"
}

# 操作系统判断 ==================================================================

# 检查操作系统名称是否为 Darwin
check_os_type () {
    local os_name
    os_name=$(uname -s)
    test 'Darwin' == "$os_name"
}

# 检查操作系统主版本是否大于 19
check_os_release () {
    local os_release
    os_release=$(uname -r)
    # 以 . 作为分隔符，将版本字符串拆分为数组，取数组中的第一个值作为主版本号
    # 其中 // 和 / 的区别在于，两个斜杠替换所有指定字符，一个斜杠只替换出现的第一个字符
    # 参考 https://blog.csdn.net/github_33736971/article/details/53980123
    local str_arr=(${os_release//./' '})
    local main_ver=${str_arr[0]}
    test 19 -lt $main_ver
}

# 从 ipa 中直接提取部分信息 ======================================================

# 从 mobileprovision 中提取 指定字段内容
extract_field_content_from_plist_content() {
    local plist_content="$1"
    local path="$2"
    local content
    content=$(echo "$plist_content" | plutil -extract "${path}" xml1 -o - -- -)
    if [[ "0" -ne "$?" ]]; then
        content='""'
    fi
    echo "$content"
}


# 提取数组字段值，以 JSON 数组形式展示
extract_field_value_array_from_plist_content() {
    local plist_content="$1"
    local path="$2"
    local val
    val=$(extract_field_content_from_plist_content "${plist_content}" "${path}" | plutil -convert json -o - -- -)
    if [[ "0" -ne "$?" ]]; then
        val='[]'
    fi
    eval "echo \"${val}\""
}


# 从 mobileprovision 中提取 指定字段值
extract_field_value_from_plist_content() {
    local plist_content="$1"
    local path="$2"
    local val
    val=$(extract_field_content_from_plist_content "${plist_content}" "${path}" | plutil -p -- -)
    eval "echo \"${val}\""
}

# 获取 ipa 信息
ipa_basic_info() {

    local ipa_file="$1"
    local INFO_PLIST
    INFO_PLIST=$(unzip -p "$ipa_file" "Payload/*.app/Info.plist" | plutil -convert xml1 -o - -- -)

    # Name
    local bundle_name
    bundle_name=$(extract_field_value_from_plist_content "$INFO_PLIST" CFBundleName)
    local display_name
    display_name=$(extract_field_value_from_plist_content "$INFO_PLIST" CFBundleDisplayName)
    echo Name: ^"$bundle_name($display_name)"

    # Version
    local short_ver
    short_ver=$(extract_field_value_from_plist_content "$INFO_PLIST" CFBundleShortVersionString)
    local bundle_ver
    bundle_ver=$(extract_field_value_from_plist_content "$INFO_PLIST" CFBundleVersion)
    echo Version: ^"$short_ver($bundle_ver)"

    # BundleID
    local bundl_id
    bundl_id=$(extract_field_value_from_plist_content "$INFO_PLIST" CFBundleIdentifier)
    echo Bundle ID: ^$bundl_id

    # SDK
    local sdk_name
    sdk_name=$(extract_field_value_from_plist_content "$INFO_PLIST" DTSDKName)
    local sdk_ver
    sdk_ver=$(extract_field_value_from_plist_content "$INFO_PLIST" DTSDKBuild)
    echo SDK: ^"$sdk_name($sdk_ver)"

    # MinimumOSVersion
    local min_os
    min_os=$(extract_field_value_from_plist_content "$INFO_PLIST" MinimumOSVersion)
    echo Minimum OS Version: ^$min_os

    # NSAppTransportSecurity
    local allows_arbitrary_loads
    allows_arbitrary_loads=$(extract_field_value_from_plist_content "$INFO_PLIST" NSAppTransportSecurity.NSAllowsArbitraryLoads)
    echo Allows Arbitrary Loads: ^$allows_arbitrary_loads

    # Xcode
    local xcode_ver
    xcode_ver=$(extract_field_value_from_plist_content "$INFO_PLIST" DTXcode)
    local xcode_build
    xcode_build=$(extract_field_value_from_plist_content "$INFO_PLIST" DTXcodeBuild)
    echo Xcode: ^"$xcode_ver($xcode_build)"

    # Machine
    local machine_os_build
    machine_os_build=$(extract_field_value_from_plist_content "$INFO_PLIST" BuildMachineOSBuild)
    echo Build Machine OS Build: ^$machine_os_build

    local back_modes
    back_modes=$(extract_field_value_array_from_plist_content "$INFO_PLIST" UIBackgroundModes)
    eval "echo Background Modes: ^\"$back_modes\""

}

# 获取 provision 信息
provision_info() {
    local ipa_file="$1"
    local PLIST_IN_MOBILEPROVISION
    PLIST_IN_MOBILEPROVISION=$(unzip -p "$ipa_file" "Payload/*.app/embedded.mobileprovision" | security cms -D)

    local provision_app_id_name
    provision_app_id_name=$(extract_field_value_from_plist_content "$PLIST_IN_MOBILEPROVISION" AppIDName)
    echo App ID Name: ^$provision_app_id_name

    local provision_name
    provision_name=$(extract_field_value_from_plist_content "$PLIST_IN_MOBILEPROVISION" Name)
    echo Name: ^$provision_name

    local provision_platform
    provision_platform=$(extract_field_value_array_from_plist_content "$PLIST_IN_MOBILEPROVISION" Platform)
    echo Platform: ^$provision_platform

    local provision_is_xcode_managed
    provision_is_xcode_managed=$(extract_field_value_from_plist_content "$PLIST_IN_MOBILEPROVISION" IsXcodeManaged)
    echo Is Xcode Managed: ^$provision_is_xcode_managed

    local provision_creation_date
    provision_creation_date=$(extract_field_value_from_plist_content "$PLIST_IN_MOBILEPROVISION" CreationDate)
    echo Creation Date: ^$provision_creation_date

    local provision_expiration_date
    provision_expiration_date=$(extract_field_value_from_plist_content "$PLIST_IN_MOBILEPROVISION" ExpirationDate)
    echo Expiration Date: ^$provision_expiration_date

    local provision_team_identifier
    provision_team_identifier=$(extract_field_value_from_plist_content "$PLIST_IN_MOBILEPROVISION" 'Entitlements.com\.apple\.developer\.team-identifier')
    echo Team Identifier: ^$provision_team_identifier

    local provision_team_name
    provision_team_name=$(extract_field_value_from_plist_content "$PLIST_IN_MOBILEPROVISION" TeamName)
    echo Team Name: ^$provision_team_name
}

# 获取 证书 信息
certificate_info() {
    local ipa_file="$1"
    local PLIST_IN_MOBILEPROVISION
    PLIST_IN_MOBILEPROVISION=$(extract_plist_in_embedded_mobileprovision "$ipa_file")

    # 第一个证书的 Base64 编码
    local dev_cer0
    dev_cer0=$(extract_field_content_from_plist_content "$PLIST_IN_MOBILEPROVISION" 'DeveloperCertificates.0' | tr -d '\n' | sed -r 's/.*<data>(.*)<\/data>.*/\1/g')

    # 起始有效期
    local cert_start_date
    cert_start_date=$(echo $dev_cer0 | base64 -Dd | openssl x509 -inform der -noout -startdate | sed -r 's/notBefore=(.*)/\1/g')
    echo Not Before: ^$cert_start_date

    # 结束有效期
    local cert_end_date
    cert_end_date=$(echo $dev_cer0 | base64 -Dd | openssl x509 -inform der -noout -enddate | sed -r 's/notAfter=(.*)/\1/g')
    echo Not After: ^$cert_end_date

    # 主题
    local cert_subject
    cert_subject=$(echo $dev_cer0 | base64 -Dd | openssl x509 -inform der -noout -subject)

    # 从 主题 中提取 UID
    local cert_uid
    cert_uid=$(echo "$cert_subject" | sed -r 's/.*UID=(.*)?\/CN=.*/\1/g')
    echo UID: ^$cert_uid

    # 从 主题 中提取 CN
    local cert_cn
    cert_cn=$(echo "$cert_subject" | sed -r 's/.*CN=(.*)?\/OU=.*/\1/g')
    echo Common Name: ^$cert_cn
}

extract_plist_in_embedded_mobileprovision() {
    local ipa_file="$1"
    unzip -p "$ipa_file" "Payload/*.app/embedded.mobileprovision" | security cms -D
}

show_package_info () {

    local ipa_file="$1"

    echo -e "\033[97;1miOS App Package:\033[0m" "$ipa_file"
    echo

    echo -e "\033[97;1m[App Information]\033[0m"
    ipa_basic_info "$ipa_file" | column -ts^
    echo

    echo -e "\033[97;1m[Provisioning Information]\033[0m"
    provision_info "$ipa_file" | column -ts^

    echo

    echo -e "\033[97;1m[Certificate Information]\033[0m"
    certificate_info "$ipa_file" | column -ts^
}


# UI ===========================================================================
# 选择证书
select_certificate() {

    # 获取所有可用于签名的证书
    local certs
    certs=$(security find-identity -v -p codesigning)

    # 计算有效行数
    local line_count=$(( $(echo "$certs" | wc -l) - 1 ))

    # 删除无用行
    certs=$(echo "$certs" | head -n $line_count)

    # 显示所有可用于签名的证书
    local prompt_text
    prompt_text=$(echo -e "${certs}\nSelect a certificate for signing: ")

    local selected_cert=''

    while [[ -z "$selected_cert" ]]; do

        read -p "$prompt_text" sel_cert_id

        prompt_text='Select a certificate for signing: '

        search_text="^  ${sel_cert_id})"

        selected_cert=$(echo "$certs" | grep "$search_text")
    done

    echo "$selected_cert"
}

# =================================== 主程序 ===================================

# 判断操作系统类型
check_os_type

if [[ "$?" -ne "0" ]]; then
    echo The OS must be 'Darwin'.
    exit 1
fi

# 判断操作系统 release 版本
check_os_release

if [[ "$?" -ne "0" ]]; then
    echo The OS release version at lease 'Darwin 11'.
    exit 1
fi


# 记录开始时间
start_time=$(date +%s)

# 指定临时工作目录的位置
TMP_WORKBENCH_ROOT='/tmp/ipa_signer'

# 参数个数
# echo $#

# 初始化变量
# ipa 文件
IPA_FILE=''
# 指定的 Mobile Provision Profile 目录
MOBILEPROVISION_PATH=''
# 指定的 Mobile Provision Profile 文件
MOBILEPROVISION_FILE=''
# 版本号
IPA_SHORT_VERSION=''
# Build 号
IPA_BUILD_VERSION=''
# 只显示 安装包 信息
SHOW_IPA_INFO_ONLY=false
# 是否需要选择证书
NEED_SELECT_CERTIFICATE=false
# 只提取 embedded.mobileprovision 中的 plist
EXTRACT_PLIST_IN_EMBEDDED_MOBILEPROVISION_ONLY=false

# 处理脚本参数
# -p Mobile Provision Profile 文件
# -s Mobile Provision Profile 所在目录
# -v 版本
# -b Build 信息
# -i 只显示 ipa 信息，然后退出
# -c 选择证书
# -e 只提取 embedded.mobileprovision 中的 plist
while getopts ":s:p:v:b:ice" opt
do
    case "$opt" in
        's')
            MOBILEPROVISION_PATH="$OPTARG"
            # 在通过命令行明确指定描述文件搜索路径的时候，要求选择证书
            NEED_SELECT_CERTIFICATE=true
            ;;
        'p')
            MOBILEPROVISION_FILE="$OPTARG"
            # 在通过命令行明确指定描述文件的时候，要求选择证书
            NEED_SELECT_CERTIFICATE=true
            ;;
        'v')
            IPA_SHORT_VERSION="$OPTARG"
            ;;
        'b')
            IPA_BUILD_VERSION="$OPTARG"
            ;;
        'i')
            SHOW_IPA_INFO_ONLY=true
            ;;
        'c')
            NEED_SELECT_CERTIFICATE=true
            ;;
        'e')
            EXTRACT_PLIST_IN_EMBEDDED_MOBILEPROVISION_ONLY=true
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
  $(basename "$0") [options] <ipa_file>

Options:
  -i                                 Show ipa information only.
  -c                                 Choose a certificate for signing.
  -e                                 Extract 'plist' content from 'embedded.mobileprovision' file.
  -p <provisioning_profile_file>     Choose a provision profile for signing.
  -s <provisioning_profiles_folder>  Specify the directory to search for the mobile provision profile.
  -v <version>                       Specify the 'Bundle version string (CFBundleShortVersionString)' of the ipa file.
  -b <build_version>                 Specify the 'Bundle version (CFBundleVersion)' of the ipa file.

EOF
    exit
fi

# ipa 文件不存在
if [[ ! -f "${IPA_FILE}" ]]; then
    echo File not exists.
    exit 1
fi


# 从安装包的 embedded.mobileprovision 中提取 plist
if [[ $EXTRACT_PLIST_IN_EMBEDDED_MOBILEPROVISION_ONLY == true ]]; then
    extract_plist_in_embedded_mobileprovision "${IPA_FILE}"
    exit
else
    # 获取原始 ipa 签名证书信息
    ORIGINAL_CERTIFICATE_NAME=$(certificate_info  "${IPA_FILE}" | grep 'Common Name: ^' | sed -r 's/Common Name: \^(.*)/\1/g')
    CERTIFICATE_NAME_FOR_SIGNING=$ORIGINAL_CERTIFICATE_NAME

    # 签名前安装包信息
    echo
    show_package_info "${IPA_FILE}"
    echo

    # 如果只显示 ipa 信息则退出
    if [[ $SHOW_IPA_INFO_ONLY == true ]]; then
        exit
    fi
fi

echo ---------------------------------------------------------------------------
echo

# 选择证书
if [[ $NEED_SELECT_CERTIFICATE == true ]]; then
    echo -e "\033[97;1mCertificates List:\033[0m"
    CERTIFICATE_NAME_FOR_SIGNING=$(select_certificate)
    echo -e "\033[93;1m${CERTIFICATE_NAME_FOR_SIGNING}\033[0m"
    # 获取证书名称，已不再使用，仅保留获取方式，备查
    # CERTIFICATE_NAME_FOR_SIGNING=$(echo "$CERTIFICATE_NAME_FOR_SIGNING" | sed -r 's/.*"(.*)"/\1/g')
    # 获取证书 ID
    CERTIFICATE_NAME_FOR_SIGNING=$(echo "$CERTIFICATE_NAME_FOR_SIGNING" | sed -r 's/.*\) (.*) ".*"/\1/g')
fi


# 获取解压缩目录
extract_path=$(extract_ipa_folder "${IPA_FILE}")
echo
echo "Extracting '${IPA_FILE}'"
echo "to         '${extract_path}/'..."

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
echo
echo -n 'Specify the main app version:'

# 指定 Version
if [[ -n "${IPA_SHORT_VERSION}" ]]; then
    echo
    echo "  Version(CFBundleShortVersionString)=${IPA_SHORT_VERSION}"
    set_short_version "${app_path}/Info.plist" "${IPA_SHORT_VERSION}"
else
    echo ' [N/A]'
fi

# 指定 Build
if [[ -n "${IPA_BUILD_VERSION}" ]]; then
    echo "  Build(CFBundleVersion)=${IPA_BUILD_VERSION}"
    set_build_version "${app_path}/Info.plist" "${IPA_BUILD_VERSION}"
fi

# 为主程序签名
echo
echo -e "Signing application \033[93;1m${app_path}/\033[0m..."
sign_code "${app_path}"

# 新 ipa 文件名
new_ipafile=$(dirname "${IPA_FILE}")/$(basename "${IPA_FILE}" .ipa)_sign_$(gen_timestamp).ipa

echo
echo -e "Packing \033[93;1m${new_ipafile}\033[0m..."

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
echo -n "Clearing workspace..."
rm -rf "$TMP_WORKBENCH_ROOT"
echo OK.

# 签名后安装包信息
echo
show_package_info "${new_ipafile}"
echo ---------------------------------------------------------------------------
echo


# 结束时间
stop_time=$(date +%s)

# 计算花费时间
elapsed_time=$(( stop_time - start_time ))

# 完成
echo
echo "Done. Totally, $elapsed_time seconds elapsed."
echo

# 打开签名后文件所在目录
open "$(dirname "${new_ipafile}")"

