登陆ssh 一键安装bash -c "$(curl https://raw.githubusercontent.com/luange/qnapxiaoya/main/update_new.sh)"

docker exec -i xiaoya sqlite3 data/data.db <<EOF
select value from x_setting_items where key = "token";
EOF
