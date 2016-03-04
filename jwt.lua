local function redkey(kid, key)
    -- get key from redis
    -- nil  (something went wrong, let the request pass)
    -- null (no such key, reject the request)
    -- key  (the key)

    local redis = require "resty.redis"
    local red = redis:new()
    red:set_timeout(100) -- 100ms

    local ok, err = red:connect(ngx.var.redhost, ngx.var.redport)
    if not ok then
        ngx.log(ngx.ERR, "failed to connect to redis: ", err)
        return nil
    end

    if ngx.var.redauth then
        local ok, err = red:auth(ngx.var.redauth)
        if not ok then
            ngx.log("failed to authenticate: ", err)
            return nil
        end
    end

    if ngx.var.reddb then
        local ok, err = red:select(ngx.var.reddb)
        if not ok then
            ngx.log("failed to select db: ", ngx.var.reddb, " ", err)
            return nil
        end
    end

    local res, err = red:hget(kid, key)
    if not res then
        ngx.log(ngx.ERR, "failed to get kid: ", kid ,", ", err)
        return nil
    end

    if res == ngx.null then
        ngx.log(ngx.ERR, "key ", kid, " not found")
        return ngx.null
    end

    local ok, err = red:close()
    if not ok then
        ngx.log(ngx.ERR, "failed to close: ", err)
    end

    return res
end


local jwt = require "resty.jwt"

local auth_header = ngx.var.http_Authorization
if auth_header == nil then
    ngx.exit(ngx.OK)
end

local _, _, token = string.find(auth_header, "Bearer%s+(.+)")
if token == nil then
    ngx.status = ngx.HTTP_UNAUTHORIZED
    ngx.log(ngx.WARN, "Missing token")
    ngx.exit(ngx.HTTP_UNAUTHORIZED)
end

local jwt_obj = jwt:load_jwt('', token)
if not jwt_obj.valid then
    ngx.status = ngx.HTTP_UNAUTHORIZED
    ngx.say("{error: 'invalid token (101)'}")
    ngx.exit(ngx.HTTP_UNAUTHORIZED)
end

local iss = jwt_obj.payload['iss']
if iss == nil then
    ngx.status = ngx.HTTP_UNAUTHORIZED
    ngx.say("{error: 'invalid token (102)'}")
    ngx.exit(ngx.HTTP_UNAUTHORIZED)
end

local jwt_dict = ngx.shared.jwt
local cert = jwt_dict:get('cert')

if cert == nil then
    local file = io.open('/lua-resty-jwt/cert.pem', 'r')
    cert = file:read("*all")
    file:close()
    jwt_dict:set('cert', cert)
end

local verified = jwt:verify_jwt_obj(cert, jwt_obj, 30)

if verified.verified then
    local private_jwt = redkey('jwt', iss)
    if private_jwt == ngx.null then
        ngx.status = ngx.HTTP_UNAUTHORIZED
        ngx.say("{error: 'session not found'}")
        ngx.exit(ngx.HTTP_UNAUTHORIZED)
    else
        ngx.req.set_header('Authorization', "Bearer "..private_jwt)
    end
else
    ngx.status = ngx.HTTP_UNAUTHORIZED
    ngx.say("{error: '"..jwt_obj.reason.."'}")
    ngx.exit(ngx.HTTP_UNAUTHORIZED)
end
