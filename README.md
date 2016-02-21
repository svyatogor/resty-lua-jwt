Acknowledgement
=======
This work is based on [lua-resty-jwt](https://github.com/SkyLothar/lua-resty-jwt) plugins so all credits.. should go those guys.
The intention of this repo is to provide an "out of the box" solution for authenticating against keys stored in Redis cache.
If you need a more versatile solution you should really turn look at the upstream project.

Version
=======
0.1

Description
===========

The intention of this repo is to provide an "out of the box" solution for authenticating against keys stored in Redis cache.
To run it in a docker container:

```
docker run --name redis redis

docker run --link redis -v nginx.conf:/usr/nginx/conf/nginx.conf svyatogor/resty-lua-jwt
```

Sample nginx.conf (minimal config with only relevant sections)

```
worker_processes  1;
daemon off;
error_log stderr;

events {
	worker_connections  1024;
}

http {
	include       mime.types;
	default_type  application/octet-stream;
	access_log    /dev/stdout;

	sendfile        on;
	keepalive_timeout  65;

	lua_package_path "/lua-resty-jwt/lib/?.lua;;";
	lua_shared_dict jwt_key_dict 10m;
	resolver 127.0.0.1;

	server {
		listen       80;
		server_name  localhost;
		set $redhost "redis";
		set $redport 6379;
		location ~ ^/api/(.*)$ {
			access_by_lua_file /lua-resty-jwt/jwt.lua;
			proxy_pass http://upstream/api/$1;
		}
	}
}
```

Integration with authentication API
=======
The token should be passed in "Authorization" header as:
```
Authorization: Bearer TOKEN
```

It must contain the payload hash of format

```
{kid: SESSION_ID}
```

During authorization process your API should set the following keys in redis:

```
HSET SESSION_ID secret SESSION_SECRET
HSET SESSION_ID data OPTIONAL_DATA
```

If you set the data (which is not required) it will be passed to the upstream API in the X-Data header. A typical use case would be to serialize relevant user data (such as user id) in the JSON hash, so that upstream API is able to identify the user.
