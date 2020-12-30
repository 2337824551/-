#!/bin/bash

VERSION="2.1.3"

PATH="/usr/local/bin:/usr/bin:/bin"

ENV_PATH="$(dirname $0)/.env"

IS_MACOS=$(uname | grep 'Darwin' | wc -l)

IS_DISPALY_CONTEXT=1

TITLE="SSPanel Auto Checkin v${VERSION} 签到通知"

COOKIE_PATH="./.ss-autocheckin.cook"

PUSH_TMP_PATH="./.ss-autocheckin.tmp"

if [ -f ${ENV_PATH} ]; then
    source ${ENV_PATH}
fi

if [ "${DISPALY_CONTEXT}" == "0" ]; then
    IS_DISPALY_CONTEXT=0
fi

if [ -z $(command -v jq) ]; then
    echo "依赖缺失: jq，查看 https://github.com/isecret/sspanel-autocheckin/blob/master/README.md 安装" && exit 1
fi

users_array=($(echo ${USERS} | tr ';' ' '))

log_text=""

if [ "${users_array}" ]; then
    user_count=1
    for user in ${users_array[@]}; do
        domain=$(echo ${user} | awk -F'----' '{print $1}')
        username=$(echo ${user} | awk -F'----' '{print $2}')
        passwd=$(echo ${user} | awk -F'----' '{print $3}')

        # 邮箱、域名脱敏处理
        username_prefix="${username%%@*}"
        username_suffix="${username#*@}"
        username_root="${username#*.}"
        username_text="${username_prefix:0:2}⁎⁎⁎@${username_suffix:0:2}⁎⁎⁎.${username_root}"

        domain_protocol="${domain%%://*}"
        domain_context="${domain##*//}"
        domain_root="${domain##*.}"
        domain_text="${domain_protocol}://${domain_context:0:2}⁎⁎⁎.${domain_root}"

        if [ -z "${domain}" ] || [ -z "${username}" ] || [ -z "${passwd}" ]; then
            echo "账号信息配置异常，请检查配置" && exit 1
        fi

        login=$(curl "${domain}/auth/login" -d "email=${username}&passwd=${passwd}&code=" -c ${COOKIE_PATH} -L -k -s)

        start_time=$(date '+%Y-%m-%d %H:%M:%S')
        login_code=$(echo ${login} | jq -r '.ret' 2>&1)
        login_status=$(echo ${login} | jq -r '.msg' 2>&1)

        login_log_text="## 用户 ${user_count}\n\n"
        login_log_text="${login_log_text}- 【签到站点】: ${domain_text}\n"
        login_log_text="${login_log_text}- 【签到用户】: ${username_text}\n"
        login_log_text="${login_log_text}- 【签到时间】: ${start_time}\n"

        if [ "${login_code}" == "1" ]; then
            userinfo=$(curl -k -s -G -b ${COOKIE_PATH} "${domain}/getuserinfo")
            user=$(echo ${userinfo} | tr '\r\n' ' ' | jq -r ".info.user" 2>&1)

            # 用户等级
            clasx=$(echo ${user} | jq -r ".class" 2>&1)
            # 等级过期时间
            class_expire=$(echo ${user} | jq -r ".class_expire" 2>&1)
            # 账户过期时间
            expire_in=$(echo ${user} | jq -r ".expire_in" 2>&1)
            # 上次签到时间
            last_check_in_time=$(echo ${user} | jq -r ".last_check_in_time" 2>&1)
            # 用户余额
            money=$(echo ${user} | jq -r ".money" 2>&1)
            # 用户限速
            node_speedlimit=$(echo ${user} | jq -r ".node_speedlimit" 2>&1)
            # 总流量
            transfer_enable=$(echo ${user} | jq -r ".transfer_enable" 2>&1)
            # 总共使用流量
            last_day_t=$(echo ${user} | jq -r ".last_day_t" 2>&1)
            # 剩余流量
            transfer_used=$(expr ${transfer_enable} - ${last_day_t})
            # 转换 GB
            transfer_enable_text=$(echo ${transfer_enable} | awk '{ byte =$1 /1024/1024**2 ; print byte " GB" }')
            last_day_t_text=$(echo ${last_day_t} | awk '{ byte =$1 /1024/1024**2 ; print byte " GB" }')
            transfer_used_text=$(echo ${transfer_used} | awk '{ byte =$1 /1024/1024**2 ; print byte " GB" }')
            # 转换上次签到时间
            if [ ${IS_MACOS} -eq 0 ]; then
                last_check_in_time_text=$(date -d "1970-01-01 UTC ${last_check_in_time} seconds" "+%F %T")
            else
                last_check_in_time_text=$(date -r ${last_check_in_time} '+%Y-%m-%d %H:%M:%S')
            fi

            user_log_text="- 【用户等级】: VIP${clasx}\n"
            user_log_text="${user_log_text}- 【用户余额】: ${money} CNY\n"
            user_log_text="${user_log_text}- 【用户限速】: ${node_speedlimit} Mbps\n"
            user_log_text="${user_log_text}- 【总流量】: ${transfer_enable_text}\n"
            user_log_text="${user_log_text}- 【剩余流量】: ${transfer_used_text}\n"
            user_log_text="${user_log_text}- 【已使用流量】: ${last_day_t_text}\n"
            user_log_text="${user_log_text}- 【等级过期时间】: ${class_expire}\n"
            user_log_text="${user_log_text}- 【账户过期时间】: ${expire_in}\n"
            user_log_text="${user_log_text}- 【上次签到时间】: ${last_check_in_time_text}\n"

            checkin=$(curl -k -s -d "" -b ${COOKIE_PATH} "${domain}/user/checkin")
            chechin_code=$(echo ${checkin} | jq -r ".ret" 2>&1)
            checkin_status=$(echo ${checkin} | jq -r ".msg" 2>&1)

            if [ "${checkin_status}" ]; then
                checkin_log_text="- 【签到状态】: ${checkin_status}\n"
            else
                checkin_log_text="- 【签到状态】: 签到失败, 请检查是否存在签到验证码\n"
            fi

            result_log_text="${login_log_text}${checkin_log_text}${user_log_text}\n\n"
        else

            result_log_text="${login_log_text}- 【签到状态】: 登录失败, 请检查配置\n\n"
        fi

        log_text="${log_text}${result_log_text}---------------------------------------\n\n"

        if [ ${IS_DISPALY_CONTEXT} == 1 ]; then
            echo -e ${log_text}
        fi

        user_count=$(expr ${user_count} + 1)
    done

    # Server 酱通知
    if [ "${PUSH_KEY}" ]; then
        echo -e "text=${TITLE}&desp=${log_text}" >${PUSH_TMP_PATH}
        push=$(curl -k -s --data-binary @${PUSH_TMP_PATH} "https://sc.ftqq.com/${PUSH_KEY}.send")
        push_code=$(echo ${push} | jq -r ".errno" 2>&1)
        if [ ${push_code} -eq 0 ]; then
            echo -e "【Server 酱推送结果】: 成功\n"
        else
            echo -e "【Server 酱推送结果】: 失败\n"
        fi
    fi

    # Qmsg 酱通知
    if [ "${QMSG_KEY}" ]; then
        result_qmsg_log_text="${TITLE}${log_text}"
        echo -e "msg=${result_qmsg_log_text}" >${PUSH_TMP_PATH}
        push=$(curl -k -s --data-binary @${PUSH_TMP_PATH} "https://qmsg.zendee.cn/send/${QMSG_KEY}")
        push_code=$(echo ${push} | jq -r ".success" 2>&1)
        if [ "${push_code}" == "true" ]; then
            echo -e "【Qmsg 酱推送结果】: 成功\n"
        else
            echo -e "【Qmsg 酱推送结果】: 失败\n"
        fi
    fi

    # TelegramBot 通知
    if [ "${TELEGRAMBOT_TOKEN}" ] && [ "${TELEGRAMBOT_CHATID}" ]; then
        result_tgbot_log_text="${TITLE}${log_text}"
        echo -e "chat_id=${TELEGRAMBOT_CHATID}&parse_mode=Markdown&text=${result_tgbot_log_text}" >${PUSH_TMP_PATH}
        push=$(curl -k -s --data-binary @${PUSH_TMP_PATH} "https://api.telegram.org/bot${TELEGRAMBOT_TOKEN}/sendMessage")
        push_code=$(echo ${push} | grep -o '"ok":true')
        if [ ${push_code} ]; then
            echo -e "【TelegramBot 推送结果】: 成功\n"
        else
            echo -e "【TelegramBot 推送结果】: 失败\n"
        fi
    fi

    rm -rf ${COOKIE_PATH}
    rm -rf ${PUSH_TMP_PATH}
else
    echo "用户组环境变量未配置" && exit 1
fi
