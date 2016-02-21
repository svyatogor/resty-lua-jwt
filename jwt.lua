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
    ngx.status = ngx.HTTP_UNAUTHORIZED
    ngx.log(ngx.WARN, "No Authorization header")
    ngx.exit(ngx.OK)
end

local _, _, token = string.find(auth_header, "Bearer%s+(.+)")
if token == nil then
    ngx.status = ngx.HTTP_UNAUTHORIZED
    ngx.log(ngx.WARN, "Missing token")
    ngx.exit(ngx.OK)
end

local jwt_obj = jwt:load_jwt('', token)
if not jwt_obj.valid then
    ngx.status = ngx.HTTP_UNAUTHORIZED
    ngx.say("{error: 'invalid token (101)'}")
    ngx.exit(ngx.OK)
end

local kid = jwt_obj.payload['kid']
if kid == nil then
    ngx.status = ngx.HTTP_UNAUTHORIZED
    ngx.say("{error: 'invalid token (102)'}")
    ngx.exit(ngx.OK)
end

local jwt_key_dict = ngx.shared.jwt_key_dict
local secret = jwt_key_dict:get(kid)
if secret == nil then
    -- key not found in cache, let's check if it's in redis
    -- new key found, if the new key is valid, older ones should be deleted
    secret = redkey(kid, 'secret')
end

if secret == ngx.null then
    -- no such key
    ngx.status = ngx.HTTP_UNAUTHORIZED
    ngx.say("{error: 'invalid or expired token'}")
    ngx.exit(ngx.OK)
elseif secret == nil then
    -- get key error
    ngx.status = ngx.HTTP_INTERNAL_SERVER_ERROR
    ngx.say("{error: 'internal error'}")
    ngx.exit(ngx.OK)
else
    local verified = jwt:verify_jwt_obj(secret, jwt_obj, 30)

    if verified.verified then
        jwt_key_dict:set(kid, secret)
        local data = redkey(kid, 'data')
        if data == ngx.null then
        else
          ngx.req.set_header('X-Data', data)
        end
    else
        ngx.status = ngx.HTTP_UNAUTHORIZED
        ngx.say("{error: '"..jwt_obj.reason.."'}")
        ngx.exit(ngx.OK)
    end
end
