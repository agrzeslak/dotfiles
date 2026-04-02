# If WSL auto-sets only HTTP proxy vars, mirror them to HTTPS/ALL proxy vars.

# Prefer lowercase vars (common on Linux), fall back to uppercase.
set -l http_p ""
if set -q http_proxy
    set http_p $http_proxy
else if set -q HTTP_PROXY
    set http_p $HTTP_PROXY
end

# If we found an HTTP proxy, ensure HTTPS equivalents exist.
if test -n "$http_p"
    # Lowercase
    if not set -q https_proxy
        set -Ux https_proxy $http_p
    end
    if not set -q all_proxy
        set -Ux all_proxy $http_p
    end

    # Uppercase
    if not set -q HTTPS_PROXY
        set -Ux HTTPS_PROXY $http_p
    end
    if not set -q ALL_PROXY
        set -Ux ALL_PROXY $http_p
    end

    # Optional: ensure NO_PROXY exists (minimal safe default)
    if not set -q no_proxy; and not set -q NO_PROXY
        set -Ux no_proxy "localhost,127.0.0.1,::1"
        set -Ux NO_PROXY $no_proxy
    else
        # Keep upper/lower in sync if one exists
        if set -q no_proxy; and not set -q NO_PROXY
            set -Ux NO_PROXY $no_proxy
        else if set -q NO_PROXY; and not set -q no_proxy
            set -Ux no_proxy $NO_PROXY
        end
    end
end

