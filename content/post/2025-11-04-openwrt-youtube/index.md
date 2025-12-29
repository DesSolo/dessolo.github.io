---
title: 'YouTube + OpenWRT'
date: '2025-11-04T16:45:07+03:00'
description: >-
  Как автоматически маршрутизировать трафик YouTube через VPN в OpenWRT с использованием официальных IP-диапазонов Google.
categories:
  - Tutorial
tags:
  - OpenWRT
  - bash
  - networking
  - YouTube
  - VPN
draft: false
---

Если вы используете OpenWRT с подключением к удалённому VPN-серверу и хотите, чтобы YouTube работал корректно без полного туннелирования всего трафика (full tunnel), вам понадобится направлять только нужные IP-адреса через VPN. Это особенно актуально при использовании **split tunneling**, когда часть трафика идёт напрямую, а часть - через VPN.

Один из способов - вручную добавлять маршруты к IP-подсетям YouTube. Однако YouTube (и другие сервисы Google) использует множество динамически меняющихся IP-адресов, поэтому поддерживать список вручную неудобно. К счастью, Google публикует актуальные IP-диапазоны в формате JSON. В этой статье мы автоматизируем добавление маршрутов к этим подсетям при поднятии VPN-интерфейса в OpenWRT.

---

## Получаем актуальные IP-диапазоны Google

Google регулярно обновляет список IP-адресов, используемых его сервисами, включая YouTube. Эти данные доступны по адресу:

🔗 [https://www.gstatic.com/ipranges/goog.json](https://www.gstatic.com/ipranges/goog.json)

Этот JSON-файл содержит как IPv4, так и IPv6 префиксы, предназначенные **для доступа к сервисам Google**, включая YouTube, Google Cloud, и другие. Более подробно о содержимом файла можно прочитать в официальной документации:

📚 [Google Cloud - IP ranges documentation](https://cloud.google.com/compute/docs/ips#ip-addresses)

---

## Создаём скрипт управления маршрутами

Создайте скрипт `/root/scripts/youtube.sh` со следующим содержимым:

```bash {file="/root/scripts/youtube.sh"}
#!/bin/sh

# update add del

set -e

DEVICE=vpn-vpn
IPV4_FILE_NAME=/tmp/ipv4_google.txt

function update {
	wget -q -O- https://www.gstatic.com/ipranges/goog.json | grep ipv4 | cut -d '"' -f 4 > $IPV4_FILE_NAME
}

function __update_if_missing {
	if [ ! -f $IPV4_FILE_NAME ]; then
		echo "updating ..."
		update
	fi
}

function __ip_ro {
	ACTION=$1

	while read line; do
		ip ro $ACTION $line dev $DEVICE
	done < $IPV4_FILE_NAME
}

function add {
	__update_if_missing
	__ip_ro add
}

function del {
	__update_if_missing
	__ip_ro del
}

$1
```

> Да, можно было бы использовать [jq](https://jqlang.org) и не приседать с `grep` и `cut`, но в условии ограниченных ресурсов роутера...
{ .prompt-info }

---

## Настраиваем автоматическое применение маршрутов

Чтобы маршруты добавлялись автоматически при поднятии VPN-интерфейса, создайте файл **hotplug-скрипта**:

```bash {file="/etc/hotplug.d/iface/99-vpn-routes"}
#!/bin/sh

[ "$INTERFACE" = "vpn" ] && [ "$ACTION" = "ifup" ] && {
    sleep 3
    /root/scripts/youtube.sh update && /root/scripts/youtube.sh add
}
```

Не забудьте сделать его исполняемым:

```bash
chmod +x /etc/hotplug.d/iface/99-vpn-routes
```

> Убедитесь, что имя интерфейса (`vpn`) соответствует имени вашего реального интерфейса в OpenWRT (например, `wg0`, `tun0` и т.д.). Также имя устройства в скрипте (`vpn-vpn`) должно соответствовать имени сетевого интерфейса, через который идёт трафик (обычно совпадает с именем интерфейса).
{ .prompt-info }

---

## Проверка работы

Переподключите интерфейс:

```bash
ifdown vpn && ifup vpn
```

После этого проверьте таблицу маршрутизации:

```bash
ip route show | grep "dev vpn-vpn"
```

Вы должны увидеть десятки (или даже сотни) строк вида:
```
8.8.8.0/24 dev vpn-vpn scope link
34.0.0.0/15 dev vpn-vpn scope link
```

---

## Дополнительно

### Ручная очистка маршрутов

Если маршруты по какой-то причине остались после отключения VPN, их можно удалить вручную:

```bash
ip ro | grep vpn-vpn | while IFS= read -r r; do ip ro del $r; done
```

### Расширение списка подсетей

Файл `goog.json` **не включает все IP-адреса YouTube**. Некоторые CDN (например, через партнёров типа YouTube Delivery или сторонние хостинги) могут использовать другие диапазоны. Если вы замечаете, что видео не загружаются, можно вручную добавить недостающие подсети, например:

```bash
# Внутри функции update, после wget:
echo "173.194.0.0/16" >> "$IPV4_FILE_NAME"
echo "216.58.192.0/19" >> "$IPV4_FILE_NAME"
```

Но учтите: такие подсети могут устаревать, поэтому лучше периодически сверяться с актуальными данными.

> Для отладки трафика используйте `tcpdump` или `dnsmasq` логи, чтобы выявить недостающие адреса или подсети.
{ .prompt-tip }

---

## Заключение

Теперь ваш OpenWRT-роутер автоматически маршрутизирует трафик YouTube через VPN, используя актуальные IP-диапазоны от Google. Это решение масштабируемо, легко поддерживается и не требует изменения DNS или перехвата трафика на уровне приложений.

Если вы используете **WireGuard**, **OpenVPN** или любой другой тип VPN - подход остаётся тем же. Главное -правильно указать имя интерфейса и устройство.

--- 

📎 **Источники**:
- [Google IP Ranges - Official JSON](https://www.gstatic.com/ipranges/goog.json)
- [Google Cloud - External IP Ranges](https://cloud.google.com/compute/docs/ips#ip-addresses)
- [OpenWRT Hotplug Documentation](https://openwrt.org/docs/guide-user/base-system/hotplug)
