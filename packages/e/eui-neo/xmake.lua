package("eui-neo")
    set_homepage("https://github.com/sudoevolve/EUI-NEO")
    set_description("Cross-platform, high-performance, low-overhead C++17 GPUI framework")
    set_license("Apache-2.0")

    add_urls("https://github.com/sudoevolve/EUI-NEO/archive/refs/tags/$(version).tar.gz")
    add_urls("https://github.com/sudoevolve/EUI-NEO.git", {alias = "git", submodules = false})

    add_versions("v0.5.8", "ca886cfb62bc05a849d2176bd6b30bbf2d0e14e1f866305ce622af6177548c8c")
    add_versions("git:dev", "e898dd58dbc9f3a194cc8fae748f0fa9f79f94f1")
    add_versions("v0.5.7", "2d3ec0a36e34b98d13dbdaf67afa4fe178cb4b52841eb17529517cb48be43551")
    add_versions("v0.5.5", "cf0da91d7544fe406b704922137fd4d55ed080b3e647501e0ca5303abb00eb98")

    add_configs("window_backend", {description = "Window backend", default = "glfw", values = {"glfw", "sdl2"}})
    add_configs("render_backend", {description = "Render backend", default = "opengl", values = {"auto", "opengl", "vulkan"}})
    add_configs("app_runner", {description = "Build the EUI application runner (defines main)", default = false, type = "boolean"})
    add_configs("markdown", {description = "Enable MD4C Markdown parsing support", default = true, type = "boolean"})
    add_configs("tray", {description = "Enable the system tray backend", default = false, type = "boolean"})
    add_configs("vulkan_low_latency", {description = "Prefer low-latency Vulkan presentation", default = false, type = "boolean"})
    -- Bump this when the port recipe changes without an upstream version bump.
    -- It participates in Xmake's package hash and forces stale binary caches to
    -- be rebuilt while keeping the public package version unchanged.
    add_configs("port_revision", {description = "Internal package port revision", default = "13", values = {"13"}, readonly = true})

    if is_plat("windows") or is_plat("mingw") then
        add_syslinks("winmm", "urlmon", "shell32", "user32", "imm32", "pdh", "comdlg32", "gdi32")
    end
    on_load(function(package)
        if package:is_plat("macosx") and
            (os.getenv("VULKAN_SDK") or "") == "" and
            (os.getenv("VK_SDK_PATH") or "") == "" then
            import("lib.detect.find_tool")
            local brew = find_tool("brew")
            if brew then
                local prefix = try {function()
                    return os.iorunv(brew.program, {"--prefix"}):trim()
                end}
                if prefix and prefix ~= "" and
                    os.isfile(path.join(prefix, "include", "vulkan", "vulkan.h")) and
                    os.isfile(path.join(prefix, "lib", "libvulkan.dylib")) then
                    os.setenv("VULKAN_SDK", prefix)
                    os.setenv("VK_SDK_PATH", prefix)
                    print("Vulkan SDK: using Homebrew prefix %s", prefix)
                end
            end
        end
        if package:is_plat("macosx") then
            -- EUI native bridge and tray code use AppKit/Objective-C for
            -- both GLFW and SDL2 window backends.
            package:add("frameworks", "Cocoa", "IOKit", "CoreFoundation")
            package:add("syslinks", "objc")
        end
        if package:config("window_backend") == "sdl2" then
            package:add("deps", "libsdl2")
        end
        if package:config("render_backend") == "vulkan" then
            package:add("deps", "vulkansdk", {system = true})
        end
        if not package:is_plat("windows", "mingw") then
            package:add("deps", "libcurl")
        end
        if package:config("app_runner") then package:add("links", "eui_app") end
        package:add("links", "eui_neo", "eui_freetype", "eui_libpng", "eui_zlib")
        if package:config("window_backend") == "glfw" then package:add("links", "eui_glfw") end
        if package:config("render_backend") == "opengl" then package:add("links", "eui_glad") end
        if package:config("markdown") then package:add("links", "eui_md4c") end
        if package:config("render_backend") == "opengl" then
            if package:is_plat("windows") or package:is_plat("mingw") then
                package:add("syslinks", "opengl32")
            elseif package:is_plat("linux") then
                package:add("syslinks", "GL")
            elseif package:is_plat("macosx") then
                package:add("frameworks", "OpenGL")
            end
        end
        if package:config("window_backend") == "glfw" then
            if package:is_plat("linux") then
                package:add("syslinks", "X11", "Xrandr", "Xinerama", "Xi", "Xcursor", "Xext", "dl", "m", "rt")
            end
        end
        if package:config("app_runner") then package:add("defines", "EUI_APP_RUNNER=1") end
    end)

    on_install("windows", "mingw", "linux", "macosx", function(package)
        os.cp(path.join(package:scriptdir(), "port", "xmake.lua"), "xmake.lua")
        -- Some JetBrains MinGW bundles ship libdep.a in bfd-plugins as an
        -- archive that GNU ar tries to load as a Windows plugin and rejects
        -- with STATUS_INVALID_IMAGE_FORMAT.  Keep package builds isolated
        -- from that host-specific plugin directory.
        if package:is_plat("windows") then
            local empty_plugins = path.join(package:builddir(), "empty-bfd-plugins")
            os.mkdir(empty_plugins)
            os.setenv("BFD_PLUGIN_PATH", empty_plugins)
        end
        local configs = {}
        configs.window_backend = package:config("window_backend")
        configs.render_backend = package:config("render_backend")
        configs.app_runner = package:config("app_runner")
        configs.markdown = package:config("markdown")
        configs.tray = package:config("tray")
        configs.vulkan_low_latency = package:config("vulkan_low_latency")
        import("package.tools.xmake").install(package, configs)
    end)

    on_test(function (package)
        -- The app variant intentionally exports a program entry point. The
        -- package snippet test also supplies main(), so skip that link-only
        -- check for this configuration.
        if package:config("app_runner") then
            return
        end
        assert(package:check_cxxsnippets({test = [[
            namespace app {
                const DslAppConfig& dslAppConfig() {
                    static const DslAppConfig config = DslAppConfig{}
                        .title("Test app")
                        .pageId("test_app")
                        .windowSize(1440, 920)
                        .fps(90.0);
                    return config;
                }
                void compose(eui::Ui& ui, const eui::Screen& screen) {
                    const bool compactHeader = screen.width < 850.0f;
                    const float headerHeight = compactHeader ? 118.0f : 92.0f;
                    ui.stack("root").size(screen.width, screen.height).content([&] {
                        ui.rect("root.background").size(screen.width, screen.height).build();
                    }).build();
                }
            }
            void test() {
                eui::Ui ui;
                ui.stack("root");
            }
        ]]}, {configs = {languages = "c++17"}, includes = "eui_neo.h"}))
    end)
