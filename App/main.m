#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

@interface MarkdownRenderer : NSObject
+ (NSString *)htmlForMarkdown:(NSString *)markdown title:(NSString *)title;
@end

@interface AppDelegate : NSObject <NSApplicationDelegate, NSTableViewDataSource, NSTableViewDelegate, WKNavigationDelegate>
@property(nonatomic, strong) NSWindow *window;
@property(nonatomic, strong) NSTextField *statusLabel;
@property(nonatomic, strong) NSTableView *tableView;
@property(nonatomic, strong) WKWebView *webView;
@property(nonatomic, strong) NSURL *selectedFolderURL;
@property(nonatomic, copy) NSArray<NSURL *> *markdownFiles;
@end

@implementation MarkdownRenderer

+ (NSString *)escapeHTML:(NSString *)string {
    NSString *escaped = [string stringByReplacingOccurrencesOfString:@"&" withString:@"&amp;"];
    escaped = [escaped stringByReplacingOccurrencesOfString:@"<" withString:@"&lt;"];
    escaped = [escaped stringByReplacingOccurrencesOfString:@">" withString:@"&gt;"];
    return escaped;
}

+ (NSString *)escapeAttribute:(NSString *)string {
    NSString *escaped = [self escapeHTML:string];
    escaped = [escaped stringByReplacingOccurrencesOfString:@"\"" withString:@"&quot;"];
    return escaped;
}

+ (NSString *)processInlineMarkdown:(NSString *)text {
    NSString *html = [self escapeHTML:text];

    NSArray<NSArray<NSString *> *> *rules = @[
        @[@"`([^`]+)`", @"<code>$1</code>"],
        @[@"!\\[([^\\]]*)\\]\\(([^\\)]+)\\)", @"<img alt=\"$1\" src=\"$2\" />"],
        @[@"\\[([^\\]]+)\\]\\(([^\\)]+)\\)", @"<a href=\"$2\">$1</a>"],
        @[@"\\*\\*([^*]+)\\*\\*", @"<strong>$1</strong>"],
        @[@"__([^_]+)__", @"<strong>$1</strong>"],
        @[@"(?<!\\*)\\*([^*]+)\\*(?!\\*)", @"<em>$1</em>"],
        @[@"(?<!_)_([^_]+)_(?!_)", @"<em>$1</em>"]
    ];

    for (NSArray<NSString *> *rule in rules) {
        NSError *error = nil;
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:rule[0]
                                                                               options:0
                                                                                 error:&error];
        if (regex != nil && error == nil) {
            html = [regex stringByReplacingMatchesInString:html
                                                   options:0
                                                     range:NSMakeRange(0, html.length)
                                              withTemplate:rule[1]];
        }
    }

    return html;
}

+ (NSString *)htmlForMarkdown:(NSString *)markdown title:(NSString *)title {
    NSArray<NSString *> *lines = [markdown componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    NSMutableString *body = [NSMutableString string];
    NSMutableArray<NSString *> *paragraphLines = [NSMutableArray array];
    __block BOOL inCodeBlock = NO;
    __block BOOL inBulletList = NO;
    __block BOOL inOrderedList = NO;
    __block BOOL inBlockquote = NO;

    void (^flushParagraph)(void) = ^{
        if (paragraphLines.count == 0) {
            return;
        }

        NSString *joined = [[paragraphLines componentsJoinedByString:@" "] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (joined.length > 0) {
            [body appendFormat:@"<p>%@</p>\n", [self processInlineMarkdown:joined]];
        }
        [paragraphLines removeAllObjects];
    };

    void (^closeListsAndQuote)(void) = ^{
        if (inBulletList) {
            [body appendString:@"</ul>\n"];
            inBulletList = NO;
        }
        if (inOrderedList) {
            [body appendString:@"</ol>\n"];
            inOrderedList = NO;
        }
        if (inBlockquote) {
            [body appendString:@"</blockquote>\n"];
            inBlockquote = NO;
        }
    };

    NSCharacterSet *whitespace = [NSCharacterSet whitespaceCharacterSet];

    for (NSString *rawLine in lines) {
        NSString *line = [rawLine stringByTrimmingCharactersInSet:whitespace];

        if ([line hasPrefix:@"```"]) {
            flushParagraph();
            closeListsAndQuote();
            if (!inCodeBlock) {
                [body appendString:@"<pre><code>"];
                inCodeBlock = YES;
            } else {
                [body appendString:@"</code></pre>\n"];
                inCodeBlock = NO;
            }
            continue;
        }

        if (inCodeBlock) {
            [body appendFormat:@"%@\n", [self escapeHTML:rawLine]];
            continue;
        }

        if (line.length == 0) {
            flushParagraph();
            closeListsAndQuote();
            continue;
        }

        if ([line hasPrefix:@"#"]) {
            flushParagraph();
            closeListsAndQuote();

            NSUInteger level = 0;
            while (level < line.length && [line characterAtIndex:level] == '#') {
                level++;
            }
            level = MAX(1, MIN(6, level));

            NSString *content = [[line substringFromIndex:level] stringByTrimmingCharactersInSet:whitespace];
            [body appendFormat:@"<h%lu>%@</h%lu>\n", (unsigned long)level, [self processInlineMarkdown:content], (unsigned long)level];
            continue;
        }

        if ([line hasPrefix:@">"]) {
            flushParagraph();
            if (!inBlockquote) {
                closeListsAndQuote();
                [body appendString:@"<blockquote>\n"];
                inBlockquote = YES;
            }
            NSString *content = [[line substringFromIndex:1] stringByTrimmingCharactersInSet:whitespace];
            [body appendFormat:@"<p>%@</p>\n", [self processInlineMarkdown:content]];
            continue;
        }

        if ([line hasPrefix:@"- "] || [line hasPrefix:@"* "]) {
            flushParagraph();
            if (!inBulletList) {
                closeListsAndQuote();
                [body appendString:@"<ul>\n"];
                inBulletList = YES;
            }
            NSString *content = [[line substringFromIndex:2] stringByTrimmingCharactersInSet:whitespace];
            [body appendFormat:@"<li>%@</li>\n", [self processInlineMarkdown:content]];
            continue;
        }

        NSError *listError = nil;
        NSRegularExpression *orderedRegex = [NSRegularExpression regularExpressionWithPattern:@"^[0-9]+\\.\\s+(.+)$"
                                                                                      options:0
                                                                                        error:&listError];
        NSTextCheckingResult *orderedMatch = [orderedRegex firstMatchInString:line
                                                                      options:0
                                                                        range:NSMakeRange(0, line.length)];
        if (orderedMatch != nil && listError == nil) {
            flushParagraph();
            if (!inOrderedList) {
                closeListsAndQuote();
                [body appendString:@"<ol>\n"];
                inOrderedList = YES;
            }
            NSRange contentRange = [orderedMatch rangeAtIndex:1];
            NSString *content = [line substringWithRange:contentRange];
            [body appendFormat:@"<li>%@</li>\n", [self processInlineMarkdown:content]];
            continue;
        }

        [paragraphLines addObject:line];
    }

    flushParagraph();
    closeListsAndQuote();

    if (inCodeBlock) {
        [body appendString:@"</code></pre>\n"];
    }

    return [NSString stringWithFormat:
            @"<!doctype html>"
             "<html>"
             "<head>"
             "<meta charset=\"utf-8\">"
             "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">"
             "<title>%@</title>"
             "<style>"
             ":root{color-scheme:light dark;--bg:#f5f1e8;--panel:#fffdf8;--text:#1f2328;--muted:#6b7280;--border:#ded6c8;--accent:#9a3412;--code:#efe7da;}"
             "@media (prefers-color-scheme: dark){:root{--bg:#171717;--panel:#202020;--text:#f3f4f6;--muted:#9ca3af;--border:#363636;--accent:#fb923c;--code:#111827;}}"
             "html,body{margin:0;padding:0;background:var(--bg);color:var(--text);font:17px/1.75 -apple-system,BlinkMacSystemFont,\"SF Pro Text\",\"PingFang SC\",sans-serif;}"
             "main{width:100%%;max-width:none;margin:0;padding:32px 36px 56px;background:var(--panel);min-height:100vh;box-sizing:border-box;}"
             "h1,h2,h3,h4,h5,h6{line-height:1.25;margin:1.4em 0 .6em;font-weight:750;}"
             "h1{font-size:2.1em;border-bottom:1px solid var(--border);padding-bottom:.35em;}"
             "h2{font-size:1.6em;border-bottom:1px solid var(--border);padding-bottom:.25em;}"
             "p,ul,ol,blockquote,pre{margin:0 0 1em;}"
             "ul,ol{padding-left:1.4em;}"
             "li{margin:.3em 0;}"
             "blockquote{border-left:4px solid var(--accent);padding:.2em 0 .2em 1em;color:var(--muted);background:color-mix(in srgb,var(--panel) 80%%,var(--accent) 20%%);border-radius:6px;}"
             "code{font:13px/1.5 ui-monospace,SFMono-Regular,Menlo,monospace;background:var(--code);padding:.14em .38em;border-radius:6px;}"
             "pre{background:var(--code);padding:16px 18px;border-radius:12px;overflow:auto;border:1px solid var(--border);}"
             "pre code{background:none;padding:0;border-radius:0;}"
             "a{color:var(--accent);text-decoration:none;}"
             "a:hover{text-decoration:underline;}"
             "img{max-width:100%%;height:auto;border-radius:10px;}"
             "hr{border:none;border-top:1px solid var(--border);margin:1.5em 0;}"
             "</style>"
             "</head>"
             "<body><main>%@</main></body></html>",
            [self escapeAttribute:title], body];
}

@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    self.markdownFiles = @[];
    [self buildMenu];
    [self buildWindow];
    [self showPlaceholder];
    [NSApp activateIgnoringOtherApps:YES];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return YES;
}

- (IBAction)openFolder:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseDirectories = YES;
    panel.canChooseFiles = NO;
    panel.allowsMultipleSelection = NO;
    panel.prompt = @"Open Folder";

    if ([panel runModal] == NSModalResponseOK) {
        [self loadFolderAtURL:panel.URL];
    }
}

- (void)buildMenu {
    NSMenu *menubar = [[NSMenu alloc] init];
    NSMenuItem *appMenuItem = [[NSMenuItem alloc] init];
    [menubar addItem:appMenuItem];
    [NSApp setMainMenu:menubar];

    NSMenu *appMenu = [[NSMenu alloc] init];
    NSString *appName = [[NSProcessInfo processInfo] processName];

    NSMenuItem *openItem = [[NSMenuItem alloc] initWithTitle:@"Open Markdown Folder..."
                                                      action:@selector(openFolder:)
                                               keyEquivalent:@"o"];
    openItem.target = self;
    [appMenu addItem:openItem];
    [appMenu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *quitItem = [[NSMenuItem alloc] initWithTitle:[@"Quit " stringByAppendingString:appName]
                                                      action:@selector(terminate:)
                                               keyEquivalent:@"q"];
    [appMenu addItem:quitItem];

    appMenuItem.submenu = appMenu;
}

- (void)buildWindow {
    NSRect frame = NSMakeRect(0, 0, 1200, 760);
    self.window = [[NSWindow alloc] initWithContentRect:frame
                                              styleMask:(NSWindowStyleMaskTitled |
                                                         NSWindowStyleMaskClosable |
                                                         NSWindowStyleMaskMiniaturizable |
                                                         NSWindowStyleMaskResizable)
                                                backing:NSBackingStoreBuffered
                                                  defer:NO];
    [self.window center];
    self.window.title = @"Markdown Reader";

    NSView *contentView = self.window.contentView;

    NSTextField *titleLabel = [self labelWithString:@"Markdown Reader"
                                               font:[NSFont boldSystemFontOfSize:28]
                                          textColor:NSColor.labelColor];
    titleLabel.frame = NSMakeRect(28, 716, 420, 32);
    titleLabel.autoresizingMask = NSViewMaxXMargin | NSViewMinYMargin;
    [contentView addSubview:titleLabel];

    self.statusLabel = [self labelWithString:@"Choose a folder. The app will scan and list all Markdown files automatically."
                                        font:[NSFont systemFontOfSize:13]
                                   textColor:NSColor.secondaryLabelColor];
    self.statusLabel.frame = NSMakeRect(30, 690, 860, 20);
    self.statusLabel.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    self.statusLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    [contentView addSubview:self.statusLabel];

    NSButton *openButton = [NSButton buttonWithTitle:@"Open Folder"
                                              target:self
                                              action:@selector(openFolder:)];
    openButton.frame = NSMakeRect(1040, 708, 130, 32);
    openButton.bezelStyle = NSBezelStyleRounded;
    openButton.autoresizingMask = NSViewMinXMargin | NSViewMinYMargin;
    [contentView addSubview:openButton];

    NSSplitView *splitView = [[NSSplitView alloc] initWithFrame:NSMakeRect(20, 20, 1160, 654)];
    splitView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    splitView.dividerStyle = NSSplitViewDividerStyleThin;
    splitView.vertical = YES;

    NSScrollView *sidebarScrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 300, 654)];
    sidebarScrollView.hasVerticalScroller = YES;
    sidebarScrollView.borderType = NSNoBorder;
    sidebarScrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    self.tableView = [[NSTableView alloc] initWithFrame:sidebarScrollView.bounds];
    self.tableView.headerView = nil;
    self.tableView.usesAlternatingRowBackgroundColors = NO;
    self.tableView.rowHeight = 28;
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.target = self;
    self.tableView.doubleAction = @selector(openSelectedRow:);

    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"File"];
    column.width = 300;
    [self.tableView addTableColumn:column];
    sidebarScrollView.documentView = self.tableView;

    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    self.webView = [[WKWebView alloc] initWithFrame:NSMakeRect(0, 0, 860, 654) configuration:config];
    self.webView.navigationDelegate = self;
    self.webView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    [splitView addSubview:sidebarScrollView];
    [splitView addSubview:self.webView];
    [splitView setPosition:300 ofDividerAtIndex:0];
    [contentView addSubview:splitView];

    [self.window makeKeyAndOrderFront:nil];
}

- (NSTextField *)labelWithString:(NSString *)string
                            font:(NSFont *)font
                       textColor:(NSColor *)textColor {
    NSTextField *label = [[NSTextField alloc] init];
    label.stringValue = string;
    label.font = font;
    label.textColor = textColor;
    label.bezeled = NO;
    label.drawsBackground = NO;
    label.editable = NO;
    label.selectable = NO;
    return label;
}

- (NSArray<NSURL *> *)scanMarkdownFilesInFolder:(NSURL *)folderURL {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSDirectoryEnumerator *enumerator = [fileManager enumeratorAtURL:folderURL
                                          includingPropertiesForKeys:@[NSURLIsRegularFileKey, NSURLNameKey]
                                                             options:NSDirectoryEnumerationSkipsHiddenFiles
                                                        errorHandler:nil];
    NSMutableArray<NSURL *> *results = [NSMutableArray array];

    for (NSURL *fileURL in enumerator) {
        NSNumber *isRegularFile = nil;
        [fileURL getResourceValue:&isRegularFile forKey:NSURLIsRegularFileKey error:nil];
        if (![isRegularFile boolValue]) {
            continue;
        }

        NSString *ext = fileURL.pathExtension.lowercaseString;
        if ([ext isEqualToString:@"md"] || [ext isEqualToString:@"markdown"]) {
            [results addObject:fileURL];
        }
    }

    [results sortUsingComparator:^NSComparisonResult(NSURL *lhs, NSURL *rhs) {
        return [[self relativePathForURL:lhs] localizedStandardCompare:[self relativePathForURL:rhs]];
    }];
    return results;
}

- (NSString *)relativePathForURL:(NSURL *)url {
    if (self.selectedFolderURL == nil) {
        return url.lastPathComponent;
    }

    NSString *basePath = self.selectedFolderURL.path;
    NSString *path = url.path;
    if ([path hasPrefix:basePath]) {
        NSString *relative = [path substringFromIndex:basePath.length];
        if ([relative hasPrefix:@"/"]) {
            relative = [relative substringFromIndex:1];
        }
        return relative.length > 0 ? relative : url.lastPathComponent;
    }
    return url.lastPathComponent;
}

- (void)loadFolderAtURL:(NSURL *)folderURL {
    self.selectedFolderURL = folderURL;
    self.markdownFiles = [self scanMarkdownFilesInFolder:folderURL];
    [self.tableView reloadData];

    if (self.markdownFiles.count == 0) {
        self.statusLabel.stringValue = [NSString stringWithFormat:@"%@  (No Markdown files found)", folderURL.path];
        self.window.title = @"Markdown Reader";
        [self showEmptyFolderMessage];
        return;
    }

    self.statusLabel.stringValue = [NSString stringWithFormat:@"%@  (%lu Markdown files)", folderURL.path, (unsigned long)self.markdownFiles.count];
    [self.tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
    [self showMarkdownAtURL:self.markdownFiles.firstObject];
}

- (void)showPlaceholder {
    NSString *html = [MarkdownRenderer htmlForMarkdown:
                      @"# 打开一个文件夹\n\n选择一个包含 Markdown 文档的文件夹，左侧会自动列出所有 `.md` 和 `.markdown` 文件。\n\n- 自动递归扫描子文件夹\n- 点击左侧文件立即预览\n- 使用更稳定的 HTML 渲染来保持排版"
                                                   title:@"Markdown Reader"];
    [self.webView loadHTMLString:html baseURL:nil];
}

- (void)showEmptyFolderMessage {
    NSString *html = [MarkdownRenderer htmlForMarkdown:
                      @"# 没找到 Markdown 文档\n\n这个文件夹里暂时没有 `.md` 或 `.markdown` 文件。你可以重新选择别的文件夹。"
                                                   title:@"No Markdown Files"];
    [self.webView loadHTMLString:html baseURL:nil];
}

- (void)showMarkdownAtURL:(NSURL *)url {
    NSError *error = nil;
    NSString *markdown = [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:&error];

    if (markdown == nil) {
        NSString *fallback = [NSString stringWithFormat:@"# 打开失败\n\n无法读取文件：`%@`\n\n%@", url.lastPathComponent, error.localizedDescription ?: @"Unknown error"];
        [self.webView loadHTMLString:[MarkdownRenderer htmlForMarkdown:fallback title:@"Read Error"] baseURL:url.URLByDeletingLastPathComponent];
        return;
    }

    NSString *title = [self relativePathForURL:url];
    NSString *html = [MarkdownRenderer htmlForMarkdown:markdown title:title];
    [self.webView loadHTMLString:html baseURL:url.URLByDeletingLastPathComponent];
    self.window.title = [NSString stringWithFormat:@"Markdown Reader - %@", title];
}

- (void)openSelectedRow:(id)sender {
    NSInteger row = self.tableView.clickedRow;
    if (row >= 0 && row < (NSInteger)self.markdownFiles.count) {
        [self showMarkdownAtURL:self.markdownFiles[(NSUInteger)row]];
    }
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return self.markdownFiles.count;
}

- (nullable NSView *)tableView:(NSTableView *)tableView
            viewForTableColumn:(nullable NSTableColumn *)tableColumn
                           row:(NSInteger)row {
    NSTableCellView *cell = [tableView makeViewWithIdentifier:@"Cell" owner:self];
    if (cell == nil) {
        cell = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, tableColumn.width, 28)];
        NSTextField *textField = [[NSTextField alloc] initWithFrame:NSMakeRect(10, 4, tableColumn.width - 16, 20)];
        textField.bezeled = NO;
        textField.drawsBackground = NO;
        textField.editable = NO;
        textField.selectable = NO;
        textField.lineBreakMode = NSLineBreakByTruncatingMiddle;
        textField.font = [NSFont systemFontOfSize:13];
        cell.identifier = @"Cell";
        cell.textField = textField;
        [cell addSubview:textField];
    }

    cell.textField.stringValue = [self relativePathForURL:self.markdownFiles[(NSUInteger)row]];
    return cell;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    NSInteger row = self.tableView.selectedRow;
    if (row >= 0 && row < (NSInteger)self.markdownFiles.count) {
        [self showMarkdownAtURL:self.markdownFiles[(NSUInteger)row]];
    }
}

- (void)webView:(WKWebView *)webView
decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction
decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    NSURL *url = navigationAction.request.URL;
    if (navigationAction.navigationType == WKNavigationTypeLinkActivated &&
        url != nil &&
        ![url.scheme.lowercaseString isEqualToString:@"about"]) {
        [[NSWorkspace sharedWorkspace] openURL:url];
        decisionHandler(WKNavigationActionPolicyCancel);
        return;
    }

    decisionHandler(WKNavigationActionPolicyAllow);
}

@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        AppDelegate *delegate = [[AppDelegate alloc] init];
        app.delegate = delegate;
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];
        [app run];
    }

    return 0;
}
