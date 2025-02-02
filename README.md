## Что это

Скрипт для обновления списка роутов в Keenetic для определенных доменов.

## Как запустить локально с помощью докер образа

1. Создать папку локально, к примеру `./keenetic-master`
1. Зайти в папку
1. Создать файл docker-compose.yml командой `wget https://raw.githubusercontent.com/antonzaytsev/keenetic-master/refs/heads/main/docker-compose.yml`
1. Создать файл domains.yml, можно самому с нуля, а можно стянуть шаблон `wget https://raw.githubusercontent.com/antonzaytsev/keenetic-master/refs/heads/main/config/domains.yml.example -O domains.yml`
1. Создать файл .env с данными доступа к роутеру (можно скопировать образец `wget https://raw.githubusercontent.com/antonzaytsev/keenetic-master/refs/heads/main/.env.example -O .env`) или воспользоваться примером ниже
```env
KEENETIC_LOGIN: admin
KEENETIC_PASSWORD: admin
KEENETIC_HOST: 192.168.0.1
KEENETIC_VPN_INTERFACES: Wireguard0,Finland
DOMAINS_FILE: ./config/domains.yml
DNS_SERVERS: 1.1.1.1,8.8.8.8
DOMAINS_MASK: 32
```
1. Запустить `docker compose up` - запустится процесс и раз в час будет обходить все группы из файла domains.yml 
   

## Как запустить локально с кодом из git

1. Вытянуть репу локально
1. Поставить ruby, лучшего всего через asdf
   1. `asdf plugin add ruby`
   2. В локальной директории запустить `asdf install ruby`
1. Скопировать несколько файлов
   ```bash
   cp config/domains.yml.example config/domains.yml && \
   cp .env.example .env
   ```
1. В файле `config/domains.yml` прописать группы доменов. Имя группы любое (по нему можно обновить ip адреса). В значения можно домены и ip адреса указывать.
1. В файле `.env` указать данные для keenetic (логин, пароль, хост и интерфейс для VPN)
1. Выполнить команду `bundle` - установит все нужные пакеты 

## Как использовать

1. Проще всего запустить `ruby cmd/crontab.rb` - раз в час будет обновлять все домены из `config/domains.yml`.
