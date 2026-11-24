/*
 * dsh-desktop-window - native WebKitGTK window for the DeepSeek Harness UI.
 *
 * The launcher starts the loopback web server, waits for its auth URL and runs
 * this program. Closing the window exits the process; the launcher then stops
 * the server. Only GTK3 and WebKit2GTK 4.1 are required (no Electron).
 */
#include <gtk/gtk.h>
#include <webkit2/webkit2.h>
#include <cairo.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const char *url;
static const char *title = "DeepSeek Harness";
static const char *icon_path;
static const char *screenshot_path;
static int width = 1280;
static int height = 840;
static int screenshot_delay_ms = 2500;
static gboolean exit_after_load;
static gboolean trace;

static void usage(FILE *out)
{
    fprintf(out,
        "usage: dsh-desktop-window --url URL [options]\n"
        "  --title TITLE              window title (default: DeepSeek Harness)\n"
        "  --icon PATH                window icon PNG\n"
        "  --width N --height N       default window size (1280x840)\n"
        "  --screenshot PATH          write a PNG snapshot after load\n"
        "  --screenshot-delay MS      delay before the snapshot (2500)\n"
        "  --exit-after-load          quit once the snapshot is written\n"
        "  --trace                    log load events to stderr\n");
}

static void on_load_changed(WebKitWebView *view, WebKitLoadEvent event, gpointer data);

static void snapshot_ready(GObject *source, GAsyncResult *result, gpointer data)
{
    (void)data;
    GError *error = NULL;
    cairo_surface_t *surface = webkit_web_view_get_snapshot_finish(WEBKIT_WEB_VIEW(source), result, &error);
    if (surface == NULL) {
        fprintf(stderr, "dsh-desktop-window: snapshot failed: %s\n",
            error != NULL ? error->message : "unknown error");
        if (error != NULL)
            g_error_free(error);
    } else {
        if (cairo_surface_write_to_png(surface, screenshot_path) != CAIRO_STATUS_SUCCESS)
            fprintf(stderr, "dsh-desktop-window: cannot write %s\n", screenshot_path);
        else if (trace)
            fprintf(stderr, "dsh-desktop-window: snapshot %s\n", screenshot_path);
        cairo_surface_destroy(surface);
    }
    fflush(stderr);
    if (exit_after_load)
        gtk_main_quit();
}

static gboolean take_snapshot(gpointer data)
{
    webkit_web_view_get_snapshot(WEBKIT_WEB_VIEW(data), WEBKIT_SNAPSHOT_REGION_VISIBLE,
        WEBKIT_SNAPSHOT_OPTIONS_NONE, NULL, snapshot_ready, NULL);
    return G_SOURCE_REMOVE;
}

static void on_load_changed(WebKitWebView *view, WebKitLoadEvent event, gpointer data)
{
    (void)data;
    if (trace) {
        const char *name = "finished";
        if (event == WEBKIT_LOAD_STARTED)
            name = "started";
        else if (event == WEBKIT_LOAD_REDIRECTED)
            name = "redirected";
        else if (event == WEBKIT_LOAD_COMMITTED)
            name = "committed";
        fprintf(stderr, "dsh-desktop-window: load %s\n", name);
        fflush(stderr);
    }
    if (event != WEBKIT_LOAD_FINISHED)
        return;
    if (screenshot_path != NULL)
        g_timeout_add((guint)screenshot_delay_ms, take_snapshot, view);
    else if (exit_after_load)
        gtk_main_quit();
}

static gboolean on_key_press(GtkWidget *widget, GdkEventKey *event, gpointer data)
{
    (void)data;
    if ((event->state & GDK_CONTROL_MASK) != 0 && (event->keyval == GDK_KEY_q || event->keyval == GDK_KEY_w)) {
        gtk_widget_destroy(widget);
        return TRUE;
    }
    if (event->keyval == GDK_KEY_F5) {
        webkit_web_view_reload(WEBKIT_WEB_VIEW(widget));
        return TRUE;
    }
    return FALSE;
}

int main(int argc, char **argv)
{
    gtk_init(&argc, &argv);

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--url") == 0 && i + 1 < argc)
            url = argv[++i];
        else if (strcmp(argv[i], "--title") == 0 && i + 1 < argc)
            title = argv[++i];
        else if (strcmp(argv[i], "--icon") == 0 && i + 1 < argc)
            icon_path = argv[++i];
        else if (strcmp(argv[i], "--width") == 0 && i + 1 < argc)
            width = atoi(argv[++i]);
        else if (strcmp(argv[i], "--height") == 0 && i + 1 < argc)
            height = atoi(argv[++i]);
        else if (strcmp(argv[i], "--screenshot") == 0 && i + 1 < argc)
            screenshot_path = argv[++i];
        else if (strcmp(argv[i], "--screenshot-delay") == 0 && i + 1 < argc)
            screenshot_delay_ms = atoi(argv[++i]);
        else if (strcmp(argv[i], "--exit-after-load") == 0)
            exit_after_load = TRUE;
        else if (strcmp(argv[i], "--trace") == 0)
            trace = TRUE;
        else if (strcmp(argv[i], "--help") == 0 || strcmp(argv[i], "-h") == 0) {
            usage(stdout);
            return 0;
        } else {
            fprintf(stderr, "dsh-desktop-window: unknown argument: %s\n", argv[i]);
            usage(stderr);
            return 2;
        }
    }
    if (url == NULL) {
        fprintf(stderr, "dsh-desktop-window: --url is required\n");
        usage(stderr);
        return 2;
    }
    if (width < 320 || height < 240) {
        fprintf(stderr, "dsh-desktop-window: window size is too small\n");
        return 2;
    }

    GtkWidget *window = gtk_window_new(GTK_WINDOW_TOPLEVEL);
    gtk_window_set_title(GTK_WINDOW(window), title);
    gtk_window_set_default_size(GTK_WINDOW(window), width, height);
    /* Deprecated in GTK 3.22 but still the only way to pin WM_CLASS, which
     * the .desktop entry's StartupWMClass matches for taskbar grouping. */
    G_GNUC_BEGIN_IGNORE_DEPRECATIONS
    gtk_window_set_wmclass(GTK_WINDOW(window), "dsh-desktop", "DshDesktop");
    G_GNUC_END_IGNORE_DEPRECATIONS
    if (icon_path != NULL && g_file_test(icon_path, G_FILE_TEST_IS_REGULAR))
        gtk_window_set_icon_from_file(GTK_WINDOW(window), icon_path, NULL);

    GtkWidget *view = webkit_web_view_new();
    WebKitSettings *settings = webkit_web_view_get_settings(WEBKIT_WEB_VIEW(view));
    webkit_settings_set_enable_developer_extras(settings, TRUE);
    webkit_settings_set_enable_html5_local_storage(settings, TRUE);
    webkit_settings_set_enable_html5_database(settings, TRUE);

    gtk_container_add(GTK_CONTAINER(window), view);
    g_signal_connect(window, "destroy", G_CALLBACK(gtk_main_quit), NULL);
    g_signal_connect(view, "key-press-event", G_CALLBACK(on_key_press), NULL);
    g_signal_connect(view, "load-changed", G_CALLBACK(on_load_changed), NULL);

    gtk_widget_show_all(window);
    webkit_web_view_load_uri(WEBKIT_WEB_VIEW(view), url);
    gtk_main();
    return 0;
}
