【1】关于安装，仅保存了3.45版本的Linux和Window
Linux安装脚本如下

```
curl -fsSL "https://raw.githubusercontent.com/guihuatu2022/alist-backup/refs/heads/main/v3.sh" -o v3.sh && bash v3.sh
```

【2】关于添加Onedrive的方法
打开`https://alist.19870802.xyz` 网址，按照相关提示设置即可

【3】关于nginx反代配置
```
location / {
  proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
  proxy_set_header X-Forwarded-Proto $scheme;
  proxy_set_header Host $http_host;
  proxy_set_header X-Real-IP $remote_addr;
  proxy_set_header Range $http_range;
  proxy_set_header If-Range $http_if_range;
  proxy_redirect off;
  proxy_pass http://127.0.0.1:5244;
  # the max size of file to upload
  client_max_body_size 20000m;
}
```
