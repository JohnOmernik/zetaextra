-- Suricata Lua file to create an equivalent to Bro's http.log (with more fields)
-- This version does JSON, CSV, or TSV output
-- Authors: Ryan Victory & Bryant Coughlin
-- Last Modified: 20170317

-- Some Notes:
--  * Fields are written in alphabetical order. This is a side effect of having one Lua script output to multiple formats
--  * TSV and CSV have a header line. TSV prefixes the header with a #, CSV does not
--  * Values that are null will be null in JSON, but in CSV and TSV we use the "NIL_STRING" as specified in the Lua script below
--  * Fields can be added or removed, in "theory" the output will automatically include the new ones
--  * We haven't really tested this on live traffic yet. Your mileage may vary in regards to speed. We can process a 250 MB
--      PCAP of HTTP traffic in about 5 seconds though, so that's promising
--  * For some reason request and response body lengths are hit or miss as to whether or not they are right. This appears to be
--      a Suricata bug, not a bug in our code. Note: Suricata shows the uncompressed size for body lengths
--  * Errors while processing a packet will show up in the suricata.log file

-- **************************************************
-- * Configuration
-- **************************************************

-- Step 1. Choose an output format. Takes either 'json', 'csv', or 'tsv' for now
LOG_OUTPUT_FORMAT = 'json'

-- Step 2. Enter your desired "null" field value (for CSV and TSV)
NULL_FIELD_VALUE = "<<NIL_VALUE>>"

-- Step 3. Choose whether or not to print a header (for CSV and TSV)
PRINT_HEADER = true

-- Step 4. Choose values for output format breaking fields
CARRIAGE_RETURN_STRING = '<CR>' -- \r
LINE_FEED_STRING = '<LF>' -- \n
TAB_STRING = '<TAB>' -- \t

-- Step 5. (Optional, potentially breaks the script) Set the keys that will be printed in the order you want them. If you leave
--          This commented out, all fields will be printed in alphabetical order by field name. CSV and TSV files will have the
--          header so you know what the fields are, JSON obviously doesn't need that
-- keys = {}

-- **************************************************
-- * End Configuration
-- **************************************************

-- Make sure that we have a valid output format
-- @note If your output format is wrong, Suricata will die without really saying anything
if (LOG_OUTPUT_FORMAT ~= 'json' and LOG_OUTPUT_FORMAT ~= 'tsv' and LOG_OUTPUT_FORMAT ~= 'csv') then
    print("[!] HTTP Logging - Invalid output format '" .. LOG_OUTPUT_FORMAT .. "'")
    print("    Please select either json, csv, or tsv")
    os.exit()
end

-- The value to use when a field is nil (null). This is different than empty.
if LOG_OUTPUT_FORMAT == 'json' then
    NIL_STRING = "null"
elseif LOG_OUTPUT_FORMAT == 'tsv' then
    NIL_STRING = NULL_FIELD_VALUE
elseif LOG_OUTPUT_FORMAT == 'csv' then
    NIL_STRING = '"' .. NULL_FIELD_VALUE .. '"'
end

-- Keep track of whether or not we have written the header (for TSV or CSV)
header_written = true
if PRINT_HEADER then
    header_written = false
end

-- Suricata Lua Output script init routine (required by Suricata)
-- @param [Table] args Arguments provided by Suricata (In testing, provides 'script_api_ver')
-- @return [Table] The requirements for this output script to be invoked for a packet/flow
function init(args)
    if args['script_api_ver'] ~= 1 then
        print "[-] HTTP Logging Lua Script has only been tested on script_api_ver 1 on Suricata 3.2.1"
    end
    local needs = {}
    needs["protocol"] = "http"
    return needs
end

-- Suricata Lua Output script setup routine (required by Suricata). Opens the log file and writes the header
-- @param [Table] args Arguments provided by Suricata (In testing, these are nil)
function setup(args)
    if LOG_OUTPUT_FORMAT == 'json' then
        --filename = SCLogPath() .. "/" .. "http.json"
        filename = '/var/log/surihttp.out'
    elseif LOG_OUTPUT_FORMAT == 'tsv' then
        filename = SCLogPath() .. "/" .. "http.tsv"
    elseif LOG_OUTPUT_FORMAT == 'csv' then
        filename = SCLogPath() .. "/" .. "http.csv"
    end
    file = assert(io.open(filename, "a")) -- Open the file in append mode

end

-- Cleans a string for JSON or TSV output
-- @param [String] str The string to clean
-- @return [String] The cleaned string
function clean(str)
    if str == nil then
        return NIL_STRING
    end

    if LOG_OUTPUT_FORMAT == 'json' then
        -- Replace newlines with \n, carriage returns with \r, tabs with \t, quotes with \"
        -- We also need to replace any '\'s with \\
        return "\"" .. string.gsub(string.gsub(string.gsub(string.gsub(string.gsub(string.gsub(str, "\\", "\\\\"), "\r\n", "\\r\\n"), "\r", "\\r"), "\t", "\\t"), "\"", "\\\""), "\n", "\\n") .. "\""
    elseif LOG_OUTPUT_FORMAT == 'tsv' then
        return string.gsub(string.gsub(string.gsub(string.gsub(str, "\r\n", CARRIAGE_RETURN_STRING .. LINE_FEED_STRING), "\r", CARRIAGE_RETURN_STRING), "\t", TAB_STRING), "\n", LINE_FEED_STRING)
    elseif LOG_OUTPUT_FORMAT == 'csv' then
        return "\"" .. string.gsub(string.gsub(string.gsub(string.gsub(string.gsub(string.gsub(str, "\\", "\\\\"), "\r\n", CARRIAGE_RETURN_STRING .. LINE_FEED_STRING), "\r", CARRIAGE_RETURN_STRING), "\t", "\t"), "\"", "\"\""), "\n", LINE_FEED_STRING) .. "\""
    end
end

-- Splits a string on space characters
-- @param [String] str The string to split
-- @return [Table] The parts of the split string in an Array-like table
function split_on_space(str)
    local parts = {}
    for i in string.gmatch(str, "%S+") do
        table.insert(parts, i)
    end
    return parts
end

-- Retrieves a value from a table, returning the NIL_STRING value if the value doesn't exist or is nil. This also cleans
--     for output using the 'clean' function
-- @param [Table] table The table to search in
-- @param [String] key The key to look for in the table
-- @return [String] The value or the NIL_STRING value
function value_or_nil(table, key)
    local value = table[key]
    return clean(value)
end

-- Used when errors want to be logged/trapped. Writes errors to STDOUT (the suricata.log file)
-- @param [String] err The error to write
function error_handler( err )
    print( "[!] HTTP Logging Error: ", err )
end

-- The Suricata Lua log entry point. Runs for any flows/packets that match the "needs" in init
-- @param [Table] args Arguments to this call (In testing, appears to only be 'tx_id' with an integer)
function log(args)
    -- Use xpcall to wrap the method, this allows us to retrieve any errors
    xpcall(wrapped_log, error_handler)
end

-- The method that actually performs the data extraction and logging
function wrapped_log()
    local data = {}
    -- Packet/Flow Information
    local seconds, microseconds = SCPacketTimestamp()


    local mydate = os.date("*t", seconds)
    local myds = string.format( "%04d", mydate.year) .. '-' .. string.format( "%02d", mydate.month) .. '-' .. string.format( "%02d", mydate.day)
    local myts = string.format( "%02d", mydate.hour) .. ':' .. string.format( "%02d", mydate.min) .. ':' .. string.format( "%02d", mydate.sec)
    local mytsutc = myds .. ' ' .. myts

    data['ts'] = seconds .. "." .. microseconds
    data['day'] = clean(myds)
    data['tsutc'] = clean(mytsutc)
    data['ip_ver'], data['src_ip'], data['dst_ip'], data['proto'], data['src_port'], data['dst_port'] = SCFlowTuple()
    _, data['raw_src_ip'], _, _, _, _ = SCPacketTuple()

    -- Paranoid cleaning of the above fields
    data['ip_ver'] = clean(data['ip_ver'])
    data['src_ip'] = clean(data['src_ip'])
    data['dst_ip'] = clean(data['dst_ip'])
    data['proto'] = clean(data['proto'])
    data['src_port'] = clean(data['src_port'])
    data['dst_port'] = clean(data['dst_port'])
    data['raw_src_ip'] = clean(data['raw_src_ip'])

    -- Retrieve the HTTP values needed
    data['req_headers'] = clean(HttpGetRawRequestHeaders())
    data['resp_headers'] = clean(HttpGetRawResponseHeaders())
    data['http_host'] = clean(HttpGetRequestHost())
    data['uri'] = clean(HttpGetRequestUriRaw())

    -- Split up the HTTP Response Line (HTTP/1.1 200 OK, etc.) on space to get the Status code/message
    -- @todo This assumes a well formed response. Maybe look for a pattern instead?
    data['http_response'] = HttpGetResponseLine()
    data['http_status_code'] = nil
    data['http_status_message'] = nil
    if data['http_response'] then
        _, data['http_status_code'], data['http_status_message'] = string.match(data['http_response'], '^(%S+)%s(%S+)%s(.+)$')
    end
    data['http_status_code'] = clean(data['http_status_code'])
    data['http_status_message'] = clean(data['http_status_message'])
    data['http_response'] = clean(data['http_response'])

    -- Split up the HTTP Request line (GET / HTTP/1.1) to retrieve the method used
    -- @todo This assumes a well formed request. Look for a pattern instead?
    data['http_request'] = HttpGetRequestLine()
    local http_request_parts = split_on_space(data['http_request'])
    data['http_method'] = clean(http_request_parts[1])
    data['http_version'] = clean(http_request_parts[3])
    data['http_request'] = clean(data['http_request'])

    -- Grab the request headers and put them into a table of key/value pairs
    -- This lowercases the header name, this allows for the headers to be properly logged even if the client didn't send
    --    them with the proper case.
    -- @note We do log the full headers in their original case later on
    local request_headers = HttpGetRequestHeaders();
    local request_headers_table = {}
    for n, v in pairs(request_headers) do
        request_headers_table[string.lower(n)] = v
    end

    -- Grab the response headers and put them into a table of key/value pairs
    -- This lowercases the header name, this allows for the headers to be properly logged even if the server didn't send
    --    them with the proper case.
    -- @note We do log the full headers in their original case later on
    local response_headers = HttpGetResponseHeaders();
    local response_headers_table = {}
    for n, v in pairs(response_headers) do
        response_headers_table[string.lower(n)] = v
    end

    -- Extract values from the request/response headers tables. New fields can be added by specifying the proper direction
    --  (request or response) and using a downcased version of the header name
    --  Example, to retrieve the value of a request header called 'My-Header' and store it in a field 'my_header':
    --          data['my_header'] = value_or_nil(request_headers_table, 'my-header')
    data['referer'] = value_or_nil(request_headers_table, 'referer')
    data['user_agent'] = value_or_nil(request_headers_table, 'user-agent')
    data['accept_encoding'] = value_or_nil(request_headers_table, 'accept-encoding')
    data['accept_language'] = value_or_nil(request_headers_table, 'accept-language')
    data['if_none_match'] = value_or_nil(request_headers_table, 'if-none-match')
    data['request_cookies'] = value_or_nil(request_headers_table, 'cookie')
    data['trusteer_rapport'] = value_or_nil(request_headers_table, 'x-trusteer-rapport')
    data['true_client_ip'] = value_or_nil(request_headers_table, 'true-client-ip')
    data['orig_content_type'] = value_or_nil(request_headers_table, 'content-type')
    data['resp_content_type'] = value_or_nil(response_headers_table, 'content-type')
    data['server_software'] = value_or_nil(response_headers_table, 'server')
    data['req_accept'] = value_or_nil(request_headers_table, 'accept')
    data['req_accept_charset'] = value_or_nil(request_headers_table, 'accept-charset')
    data['if_modified_since'] = value_or_nil(request_headers_table, 'if-modified-since')
    data['connection'] = value_or_nil(request_headers_table, 'connection')
    data['resp_cookies'] = value_or_nil(response_headers_table, 'set-cookie')
    data['resp_location'] = value_or_nil(response_headers_table, 'location')
    data['x_forwarded_for'] = value_or_nil(request_headers_table, 'x-forwarded-for')
    data['req_content_length'] = value_or_nil(request_headers_table, 'content-length')
    data['resp_content_length'] = value_or_nil(response_headers_table, 'content-length')

    -- Retrieve the request body to get the POST data
    local request_body, request_body_offset, request_body_end = HttpGetRequestBody()
    -- local request_body_pairs = {}
    data['request_body_str'] = NIL_STRING
    if request_body then
        data['request_body_str'] = clean(table.concat(request_body, ''))
    end

    -- Calculate the request body length
    data['request_body_length'] = 0
    if (request_body_offset and request_body_end) then
        data['request_body_length'] = request_body_end - request_body_offset
    end

    -- Calculate the response body length
    -- @todo This appears to not be accurate in all cases.
    local response_body, response_body_offset, response_body_end = HttpGetResponseBody()
    data['response_body_length'] = 0
    if (response_body_offset and response_body_end) then
        data['response_body_length'] = response_body_end - response_body_offset
    end

    -- Lua doesn't maintain order of insertion for tables. We will sort the keys and pass
    --  them into the log functions to ensure that every row has the exact same key orders
    -- !!!!!! NOTE !!!!!!
    -- We are going to cache this value. For most uses this is OK, but if this script is modified so that you don't create
    --  the same keys in the data every time, you can't cache the keys
    if keys == nil then
        keys = {}
        for n in pairs(data) do table.insert(keys, n) end
        table.sort(keys)
    end

    if LOG_OUTPUT_FORMAT == 'json' then
        log_json(data, keys)
    elseif LOG_OUTPUT_FORMAT == 'tsv' then
        log_tsv(data, keys)
    elseif LOG_OUTPUT_FORMAT == 'csv' then
        log_csv(data, keys)
    end

end

-- Logs the given data as JSON
-- @param [Table] data The data to output
-- @param [Table] keys The keys in the order they should be outputted
function log_json(data, keys)
    local output_data = {}
    for i, key in ipairs(keys) do
        table.insert(output_data, '"' .. key .. '":' .. data[key])
    end
    file:write('{')
    file:write(table.concat(output_data, ','))
    file:write("}\n")
    file:flush()
end

-- Logs the given data as TSV
-- @param [Table] data The data to output
-- @param [Table] keys The keys in the order they should be outputted
function log_tsv(data, keys)
    if header_written ~= true then
        -- We need to write out the file header
        local columns = {}
        for _, key in ipairs(keys) do table.insert(columns, key) end
        file:write('#' .. table.concat(columns, "\t") .. "\n")
        header_written = true
    end

    local output_data = {}
    for _, key in ipairs(keys) do
        table.insert(output_data, data[key])
    end
    file:write(table.concat(output_data, "\t") .. "\n")
    file:flush()
end

-- Logs the given data as CSV
-- @param [Table] data The data to output
-- @param [Table] keys The keys in the order they should be outputted
function log_csv(data, keys)
    if header_written ~= true then
        -- We need to write out the file header
        local columns = {}
        for _, key in ipairs(keys) do table.insert(columns, '"' .. key .. '"') end
        file:write(table.concat(columns, ",") .. "\n")
        header_written = true
    end

    local output_data = {}
    for _, key in ipairs(keys) do
        table.insert(output_data, data[key])
    end
    file:write(table.concat(output_data, ",") .. "\n")
    file:flush()
end

-- Runs when Suricata is shutting down this output script. This closes the output file.
-- @param [Table] args Arguments (not sure what these do yet)
function deinit(args)
    file:close(file)
end
