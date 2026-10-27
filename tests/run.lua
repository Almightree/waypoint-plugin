local files = { "tests/Navigation.test.lua", "tests/Display.test.lua", "tests/WaypointProbe.test.lua" }
for _, file in ipairs(files) do
    local ok, err = pcall(dofile, file)
    if not ok then
        io.stderr:write(file .. ": " .. tostring(err) .. "\n")
        os.exit(1)
    end
end
io.write("All prototype and probe tests passed\n")
