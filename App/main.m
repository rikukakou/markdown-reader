#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

@protocol FolderDropHandling <NSObject>
- (void)handleDroppedFolderURL:(NSURL *)url;
@end

@interface FileNode : NSObject
@property(nonatomic, copy) NSString *name;
@property(nonatomic, copy) NSString *relativePath;
@property(nonatomic, strong, nullable) NSURL *fileURL;
@property(nonatomic, strong) NSMutableArray<FileNode *> *children;
@property(nonatomic, weak, nullable) FileNode *parent;
@property(nonatomic, assign) BOOL directory;
+ (instancetype)directoryNodeWithName:(NSString *)name relativePath:(NSString *)relativePath;
+ (instancetype)fileNodeWithName:(NSString *)name relativePath:(NSString *)relativePath fileURL:(NSURL *)fileURL;
- (BOOL)isLeaf;
@end

@interface DropContentView : NSView <NSDraggingDestination>
@property(nonatomic, weak) id<FolderDropHandling> dropDelegate;
@end

@interface MarkdownRenderer : NSObject
+ (NSString *)htmlForMarkdown:(NSString *)markdown title:(NSString *)title;
@end

@interface AppDelegate : NSObject <NSApplicationDelegate, NSOutlineViewDataSource, NSOutlineViewDelegate, NSSearchFieldDelegate, WKNavigationDelegate, FolderDropHandling, NSWindowDelegate>
@property(nonatomic, strong) NSWindow *window;
@property(nonatomic, strong) NSTextField *statusLabel;
@property(nonatomic, strong) NSSearchField *searchField;
@property(nonatomic, strong) NSOutlineView *outlineView;
@property(nonatomic, strong) WKWebView *webView;
@property(nonatomic, strong) NSSplitView *splitView;
@property(nonatomic, strong) NSView *sidebarContainer;
@property(nonatomic, strong) NSView *previewContainer;
@property(nonatomic, strong) NSURL *selectedFolderURL;
@property(nonatomic, copy) NSArray<NSURL *> *markdownFiles;
@property(nonatomic, strong) FileNode *rootNode;
@property(nonatomic, copy) NSString *searchQuery;
@end

@implementation FileNode

+ (instancetype)directoryNodeWithName:(NSString *)name relativePath:(NSString *)relativePath {
    FileNode *node = [[FileNode alloc] init];
    node.name = name;
    node.relativePath = relativePath;
    node.children = [NSMutableArray array];
    node.directory = YES;
    return node;
}

+ (instancetype)fileNodeWithName:(NSString *)name relativePath:(NSString *)relativePath fileURL:(NSURL *)fileURL {
    FileNode *node = [[FileNode alloc] init];
    node.name = name;
    node.relativePath = relativePath;
    node.fileURL = fileURL;
    node.children = [NSMutableArray array];
    node.directory = NO;
    return node;
}

- (BOOL)isLeaf {
    return !self.directory;
}

@end

@implementation DropContentView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        [self registerForDraggedTypes:@[NSPasteboardTypeFileURL]];
    }
    return self;
}

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
    NSPasteboard *pasteboard = sender.draggingPasteboard;
    if ([self folderURLFromPasteboard:pasteboard] != nil) {
        return NSDragOperationCopy;
    }
    return NSDragOperationNone;
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
    NSURL *url = [self folderURLFromPasteboard:sender.draggingPasteboard];
    if (url == nil) {
        return NO;
    }

    [self.dropDelegate handleDroppedFolderURL:url];
    return YES;
}

- (nullable NSURL *)folderURLFromPasteboard:(NSPasteboard *)pasteboard {
    NSArray<NSURL *> *urls = [pasteboard readObjectsForClasses:@[[NSURL class]]
                                                       options:@{NSPasteboardURLReadingFileURLsOnlyKey: @YES}];
    for (NSURL *url in urls) {
        NSNumber *isDirectory = nil;
        [url getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:nil];
        if (isDirectory.boolValue) {
            return url;
        }
    }
    return nil;
}

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

+ (NSArray<NSString *> *)tableCellsFromLine:(NSString *)line {
    NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if ([trimmed hasPrefix:@"|"]) {
        trimmed = [trimmed substringFromIndex:1];
    }
    if ([trimmed hasSuffix:@"|"]) {
        trimmed = [trimmed substringToIndex:trimmed.length - 1];
    }

    NSArray<NSString *> *parts = [trimmed componentsSeparatedByString:@"|"];
    NSMutableArray<NSString *> *cells = [NSMutableArray arrayWithCapacity:parts.count];
    for (NSString *part in parts) {
        [cells addObject:[part stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]];
    }
    return cells;
}

+ (BOOL)isTableSeparatorLine:(NSString *)line {
    NSString *trimmed = [[line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] stringByReplacingOccurrencesOfString:@"|" withString:@""];
    if (trimmed.length == 0) {
        return NO;
    }

    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@":- "];
    return [[trimmed stringByTrimmingCharactersInSet:allowed] length] == 0 && [trimmed containsString:@"-"];
}

+ (BOOL)isHorizontalRule:(NSString *)line {
    NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (trimmed.length < 3) {
        return NO;
    }

    NSString *candidate = [trimmed stringByReplacingOccurrencesOfString:@" " withString:@""];
    return [candidate isEqualToString:@"---"] ||
           [candidate isEqualToString:@"***"] ||
           [candidate isEqualToString:@"___"] ||
           [candidate hasPrefix:@"---"] ||
           [candidate hasPrefix:@"***"] ||
           [candidate hasPrefix:@"___"];
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
    NSError *orderedListError = nil;
    NSRegularExpression *orderedRegex = [NSRegularExpression regularExpressionWithPattern:@"^[0-9]+\\.\\s+(.+)$"
                                                                                  options:0
                                                                                    error:&orderedListError];
    NSError *taskListError = nil;
    NSRegularExpression *taskRegex = [NSRegularExpression regularExpressionWithPattern:@"^[-*]\\s+\\[([ xX])\\]\\s+(.+)$"
                                                                               options:0
                                                                                 error:&taskListError];

    for (NSUInteger index = 0; index < lines.count; index++) {
        NSString *rawLine = lines[index];
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

        if ([self isHorizontalRule:line]) {
            flushParagraph();
            closeListsAndQuote();
            [body appendString:@"<hr />\n"];
            continue;
        }

        if ([line containsString:@"|"] &&
            index + 1 < lines.count &&
            [self isTableSeparatorLine:lines[index + 1]]) {
            flushParagraph();
            closeListsAndQuote();

            NSArray<NSString *> *headerCells = [self tableCellsFromLine:line];
            [body appendString:@"<table><thead><tr>"];
            for (NSString *cell in headerCells) {
                [body appendFormat:@"<th>%@</th>", [self processInlineMarkdown:cell]];
            }
            [body appendString:@"</tr></thead><tbody>"];

            index += 2;
            while (index < lines.count) {
                NSString *tableLine = [lines[index] stringByTrimmingCharactersInSet:whitespace];
                if (tableLine.length == 0 || ![tableLine containsString:@"|"]) {
                    index--;
                    break;
                }

                NSArray<NSString *> *cells = [self tableCellsFromLine:tableLine];
                [body appendString:@"<tr>"];
                for (NSString *cell in cells) {
                    [body appendFormat:@"<td>%@</td>", [self processInlineMarkdown:cell]];
                }
                [body appendString:@"</tr>"];
                index++;
            }
            [body appendString:@"</tbody></table>\n"];
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

        NSTextCheckingResult *taskMatch = [taskRegex firstMatchInString:line options:0 range:NSMakeRange(0, line.length)];
        if (taskMatch != nil && taskListError == nil) {
            flushParagraph();
            if (!inBulletList) {
                closeListsAndQuote();
                [body appendString:@"<ul class=\"task-list\">\n"];
                inBulletList = YES;
            }
            NSString *state = [line substringWithRange:[taskMatch rangeAtIndex:1]];
            NSString *content = [line substringWithRange:[taskMatch rangeAtIndex:2]];
            BOOL checked = [[state lowercaseString] isEqualToString:@"x"];
            [body appendFormat:@"<li class=\"task-item\"><span class=\"task-checkbox%@\"></span><span>%@</span></li>\n",
             checked ? @" checked" : @"",
             [self processInlineMarkdown:content]];
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

        NSTextCheckingResult *orderedMatch = [orderedRegex firstMatchInString:line
                                                                      options:0
                                                                        range:NSMakeRange(0, line.length)];
        if (orderedMatch != nil && orderedListError == nil) {
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
             ":root{color-scheme:light dark;--bg:#eee6d6;--panel:#fffdf8;--text:#1f2328;--muted:#6b7280;--border:#ded6c8;--accent:#9a3412;--accent-soft:#f4d7bf;--code:#efe7da;}"
             "@media (prefers-color-scheme: dark){:root{--bg:#151515;--panel:#202020;--text:#f3f4f6;--muted:#9ca3af;--border:#393939;--accent:#fb923c;--accent-soft:#4a2d1d;--code:#111827;}}"
             "html,body{width:100%%;height:100%%;margin:0;padding:0;background:var(--bg);color:var(--text);font:17px/1.75 -apple-system,BlinkMacSystemFont,\"SF Pro Text\",\"PingFang SC\",sans-serif;}"
             "body{display:block;}"
             "main{width:100%%;min-width:100%%;margin:0;padding:28px 34px 52px;background:var(--panel);min-height:100vh;box-sizing:border-box;}"
             "h1,h2,h3,h4,h5,h6{line-height:1.25;margin:1.4em 0 .6em;font-weight:750;}"
             "h1{font-size:2.1em;border-bottom:1px solid var(--border);padding-bottom:.35em;}"
             "h2{font-size:1.6em;border-bottom:1px solid var(--border);padding-bottom:.25em;}"
             "p,ul,ol,blockquote,pre,table{margin:0 0 1em;}"
             "ul,ol{padding-left:1.4em;}"
             "li{margin:.3em 0;}"
             ".task-list{list-style:none;padding-left:0;}"
             ".task-item{display:flex;align-items:flex-start;gap:12px;}"
             ".task-checkbox{width:18px;height:18px;border-radius:6px;border:1px solid var(--border);background:var(--panel);margin-top:.28em;flex:none;}"
             ".task-checkbox.checked{background:var(--accent);border-color:var(--accent);box-shadow:inset 0 0 0 4px var(--panel);}"
             "blockquote{border-left:4px solid var(--accent);padding:.2em 0 .2em 1em;color:var(--muted);background:var(--accent-soft);border-radius:6px;}"
             "code{font:13px/1.5 ui-monospace,SFMono-Regular,Menlo,monospace;background:var(--code);padding:.14em .38em;border-radius:6px;}"
             "pre{background:var(--code);padding:16px 18px;border-radius:12px;overflow:auto;border:1px solid var(--border);}"
             "pre code{background:none;padding:0;border-radius:0;}"
             "a{color:var(--accent);text-decoration:none;}"
             "a:hover{text-decoration:underline;}"
             "img{display:block;max-width:100%%;height:auto;border-radius:10px;}"
             "table{width:100%%;border-collapse:collapse;border-spacing:0;display:table;overflow-x:auto;}"
             "thead th{background:var(--accent-soft);font-weight:700;}"
             "th,td{border:1px solid var(--border);padding:10px 12px;text-align:left;vertical-align:top;}"
             "tbody tr:nth-child(even){background:color-mix(in srgb,var(--panel) 85%%,var(--accent-soft) 15%%);}"
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
    self.searchQuery = @"";
    self.rootNode = [FileNode directoryNodeWithName:@"Root" relativePath:@""];
    [self buildMenu];
    [self buildWindow];
    [self showPlaceholder];
    [NSApp activateIgnoringOtherApps:YES];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return YES;
}

- (void)windowDidResize:(NSNotification *)notification {
    [self layoutSplitViewSubviews];
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

- (void)handleDroppedFolderURL:(NSURL *)url {
    [self loadFolderAtURL:url];
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
    NSRect frame = NSMakeRect(0, 0, 1280, 800);
    self.window = [[NSWindow alloc] initWithContentRect:frame
                                              styleMask:(NSWindowStyleMaskTitled |
                                                         NSWindowStyleMaskClosable |
                                                         NSWindowStyleMaskMiniaturizable |
                                                         NSWindowStyleMaskResizable)
                                                backing:NSBackingStoreBuffered
                                                  defer:NO];
    [self.window center];
    self.window.title = @"Markdown Reader";
    self.window.minSize = NSMakeSize(980, 620);
    self.window.delegate = self;

    DropContentView *contentView = [[DropContentView alloc] initWithFrame:self.window.contentView.bounds];
    contentView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    contentView.dropDelegate = self;
    self.window.contentView = contentView;

    NSTextField *titleLabel = [self labelWithString:@"Markdown Reader"
                                               font:[NSFont boldSystemFontOfSize:28]
                                          textColor:NSColor.labelColor];
    titleLabel.frame = NSMakeRect(28, 756, 360, 32);
    titleLabel.autoresizingMask = NSViewMaxXMargin | NSViewMinYMargin;
    [contentView addSubview:titleLabel];

    self.statusLabel = [self labelWithString:@"Choose or drag in a folder. The app will scan all Markdown files automatically."
                                        font:[NSFont systemFontOfSize:13]
                                   textColor:NSColor.secondaryLabelColor];
    self.statusLabel.frame = NSMakeRect(30, 730, 780, 20);
    self.statusLabel.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    self.statusLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    [contentView addSubview:self.statusLabel];

    self.searchField = [[NSSearchField alloc] initWithFrame:NSMakeRect(760, 750, 250, 30)];
    self.searchField.placeholderString = @"Search files";
    self.searchField.delegate = self;
    self.searchField.autoresizingMask = NSViewMinXMargin | NSViewMinYMargin;
    [contentView addSubview:self.searchField];

    NSButton *openButton = [NSButton buttonWithTitle:@"Open Folder"
                                              target:self
                                              action:@selector(openFolder:)];
    openButton.frame = NSMakeRect(1040, 748, 210, 32);
    openButton.bezelStyle = NSBezelStyleRounded;
    openButton.autoresizingMask = NSViewMinXMargin | NSViewMinYMargin;
    [contentView addSubview:openButton];

    self.splitView = [[NSSplitView alloc] initWithFrame:NSMakeRect(20, 20, 1240, 700)];
    self.splitView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.splitView.dividerStyle = NSSplitViewDividerStyleThin;
    self.splitView.vertical = YES;

    self.sidebarContainer = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 320, 700)];
    self.sidebarContainer.autoresizingMask = NSViewHeightSizable;

    NSScrollView *sidebarScrollView = [[NSScrollView alloc] initWithFrame:self.sidebarContainer.bounds];
    sidebarScrollView.hasVerticalScroller = YES;
    sidebarScrollView.borderType = NSNoBorder;
    sidebarScrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    self.outlineView = [[NSOutlineView alloc] initWithFrame:sidebarScrollView.bounds];
    self.outlineView.headerView = nil;
    self.outlineView.rowHeight = 28;
    self.outlineView.indentationPerLevel = 16;
    self.outlineView.floatsGroupRows = NO;
    self.outlineView.delegate = self;
    self.outlineView.dataSource = self;
    self.outlineView.target = self;
    self.outlineView.doubleAction = @selector(openSelectedItem:);

    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"File"];
    column.width = 320;
    [self.outlineView addTableColumn:column];
    self.outlineView.outlineTableColumn = column;
    sidebarScrollView.documentView = self.outlineView;
    [self.sidebarContainer addSubview:sidebarScrollView];

    self.previewContainer = [[NSView alloc] initWithFrame:NSMakeRect(320, 0, 920, 700)];
    self.previewContainer.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    self.webView = [[WKWebView alloc] initWithFrame:self.previewContainer.bounds configuration:config];
    self.webView.navigationDelegate = self;
    self.webView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.webView.allowsMagnification = YES;
    [self.webView setValue:@NO forKey:@"drawsBackground"];
    [self.previewContainer addSubview:self.webView];

    [self.splitView addSubview:self.sidebarContainer];
    [self.splitView addSubview:self.previewContainer];
    [self.splitView setHoldingPriority:NSLayoutPriorityDragThatCanResizeWindow forSubviewAtIndex:0];
    [self.splitView setHoldingPriority:NSLayoutPriorityDefaultLow forSubviewAtIndex:1];
    [contentView addSubview:self.splitView];
    [self layoutSplitViewSubviews];

    [self.window makeKeyAndOrderFront:nil];
}

- (void)layoutSplitViewSubviews {
    if (self.splitView.subviews.count < 2) {
        return;
    }

    NSRect bounds = self.splitView.bounds;
    CGFloat dividerThickness = self.splitView.dividerThickness;
    CGFloat preferredSidebarWidth = 320.0;
    CGFloat minSidebarWidth = 260.0;
    CGFloat maxSidebarWidth = 420.0;
    CGFloat availableWidth = bounds.size.width - dividerThickness;
    CGFloat sidebarWidth = MIN(maxSidebarWidth, MAX(minSidebarWidth, preferredSidebarWidth));
    sidebarWidth = MIN(sidebarWidth, MAX(availableWidth * 0.45, minSidebarWidth));
    CGFloat previewWidth = MAX(availableWidth - sidebarWidth, 320.0);

    self.sidebarContainer.frame = NSMakeRect(0, 0, sidebarWidth, bounds.size.height);
    self.previewContainer.frame = NSMakeRect(sidebarWidth + dividerThickness, 0, previewWidth, bounds.size.height);
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
                                          includingPropertiesForKeys:@[NSURLIsRegularFileKey]
                                                             options:NSDirectoryEnumerationSkipsHiddenFiles
                                                        errorHandler:nil];
    NSMutableArray<NSURL *> *results = [NSMutableArray array];

    for (NSURL *fileURL in enumerator) {
        NSNumber *isRegularFile = nil;
        [fileURL getResourceValue:&isRegularFile forKey:NSURLIsRegularFileKey error:nil];
        if (!isRegularFile.boolValue) {
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

- (FileNode *)treeForFiles:(NSArray<NSURL *> *)files {
    FileNode *root = [FileNode directoryNodeWithName:@"Root" relativePath:@""];
    NSMutableDictionary<NSString *, FileNode *> *directories = [NSMutableDictionary dictionary];
    directories[@""] = root;

    for (NSURL *url in files) {
        NSString *relativePath = [self relativePathForURL:url];
        NSArray<NSString *> *components = [relativePath pathComponents];
        NSMutableString *currentPath = [NSMutableString string];
        FileNode *parent = root;

        for (NSUInteger index = 0; index < components.count; index++) {
            NSString *component = components[index];
            BOOL last = (index == components.count - 1);

            if (currentPath.length > 0) {
                [currentPath appendString:@"/"];
            }
            [currentPath appendString:component];

            if (last) {
                FileNode *fileNode = [FileNode fileNodeWithName:component
                                                   relativePath:[currentPath copy]
                                                        fileURL:url];
                fileNode.parent = parent;
                [parent.children addObject:fileNode];
                continue;
            }

            FileNode *directory = directories[currentPath];
            if (directory == nil) {
                directory = [FileNode directoryNodeWithName:component relativePath:[currentPath copy]];
                directory.parent = parent;
                directories[currentPath] = directory;
                [parent.children addObject:directory];
            }
            parent = directory;
        }
    }

    [self sortNodeRecursively:root];
    return root;
}

- (void)sortNodeRecursively:(FileNode *)node {
    [node.children sortUsingComparator:^NSComparisonResult(FileNode *lhs, FileNode *rhs) {
        if (lhs.directory != rhs.directory) {
            return lhs.directory ? NSOrderedAscending : NSOrderedDescending;
        }
        return [lhs.name localizedStandardCompare:rhs.name];
    }];

    for (FileNode *child in node.children) {
        [self sortNodeRecursively:child];
    }
}

- (NSArray<NSURL *> *)filteredMarkdownFiles {
    NSString *query = [self.searchQuery stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (query.length == 0) {
        return self.markdownFiles;
    }

    NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(NSURL *url, NSDictionary<NSString *, id> *bindings) {
        return [[[self relativePathForURL:url] lowercaseString] containsString:[query lowercaseString]];
    }];
    return [self.markdownFiles filteredArrayUsingPredicate:predicate];
}

- (void)reloadSidebarPreservingSelection {
    NSURL *selectedURL = [self selectedFileURL];
    self.rootNode = [self treeForFiles:[self filteredMarkdownFiles]];
    [self.outlineView reloadData];
    [self.outlineView expandItem:nil expandChildren:YES];

    if (selectedURL != nil) {
        FileNode *node = [self findNodeForURL:selectedURL inNode:self.rootNode];
        if (node != nil) {
            NSInteger row = [self.outlineView rowForItem:node];
            if (row >= 0) {
                [self.outlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
            }
        }
    }
}

- (nullable FileNode *)findNodeForURL:(NSURL *)url inNode:(FileNode *)node {
    if (!node.directory && [node.fileURL isEqual:url]) {
        return node;
    }

    for (FileNode *child in node.children) {
        FileNode *match = [self findNodeForURL:url inNode:child];
        if (match != nil) {
            return match;
        }
    }
    return nil;
}

- (nullable NSURL *)selectedFileURL {
    id item = [self.outlineView itemAtRow:self.outlineView.selectedRow];
    if ([item isKindOfClass:[FileNode class]]) {
        FileNode *node = item;
        return node.fileURL;
    }
    return nil;
}

- (void)loadFolderAtURL:(NSURL *)folderURL {
    self.selectedFolderURL = folderURL;
    self.markdownFiles = [self scanMarkdownFilesInFolder:folderURL];
    [self reloadSidebarPreservingSelection];

    if (self.markdownFiles.count == 0) {
        self.statusLabel.stringValue = [NSString stringWithFormat:@"%@  (No Markdown files found)", folderURL.path];
        self.window.title = @"Markdown Reader";
        [self showEmptyFolderMessage];
        return;
    }

    self.statusLabel.stringValue = [NSString stringWithFormat:@"%@  (%lu Markdown files, drag another folder to replace)", folderURL.path, (unsigned long)self.markdownFiles.count];
    FileNode *firstNode = [self firstLeafNodeInNode:self.rootNode];
    if (firstNode != nil) {
        NSInteger row = [self.outlineView rowForItem:firstNode];
        if (row >= 0) {
            [self.outlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
        }
        [self showMarkdownAtURL:firstNode.fileURL];
    }
}

- (nullable FileNode *)firstLeafNodeInNode:(FileNode *)node {
    for (FileNode *child in node.children) {
        if (child.directory) {
            FileNode *leaf = [self firstLeafNodeInNode:child];
            if (leaf != nil) {
                return leaf;
            }
        } else {
            return child;
        }
    }
    return nil;
}

- (void)showPlaceholder {
    NSString *html = [MarkdownRenderer htmlForMarkdown:
                      @"# 打开一个文件夹\n\n选择一个包含 Markdown 文档的文件夹，左侧会自动构建目录树，右侧全宽预览内容。\n\n- 自动递归扫描子文件夹\n- 支持搜索文件名和路径\n- 支持表格、任务列表、代码块\n- 支持直接拖拽文件夹到窗口"
                                                   title:@"Markdown Reader"];
    [self.webView loadHTMLString:html baseURL:nil];
}

- (void)showEmptyFolderMessage {
    NSString *html = [MarkdownRenderer htmlForMarkdown:
                      @"# 没找到 Markdown 文档\n\n这个文件夹里暂时没有 `.md` 或 `.markdown` 文件。你可以重新选择别的文件夹，或者把文件夹直接拖进窗口。"
                                                   title:@"No Markdown Files"];
    [self.webView loadHTMLString:html baseURL:nil];
}

- (void)showMarkdownAtURL:(NSURL *)url {
    if (url == nil) {
        return;
    }

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

- (void)openSelectedItem:(id)sender {
    id item = [self.outlineView itemAtRow:self.outlineView.clickedRow];
    if (![item isKindOfClass:[FileNode class]]) {
        return;
    }

    FileNode *node = item;
    if (node.directory) {
        if ([self.outlineView isItemExpanded:node]) {
            [self.outlineView collapseItem:node];
        } else {
            [self.outlineView expandItem:node];
        }
        return;
    }

    [self showMarkdownAtURL:node.fileURL];
}

- (void)controlTextDidChange:(NSNotification *)obj {
    self.searchQuery = self.searchField.stringValue ?: @"";
    [self reloadSidebarPreservingSelection];

    if (self.rootNode.children.count == 0) {
        NSString *html = [MarkdownRenderer htmlForMarkdown:
                          @"# 没有匹配文件\n\n换个关键字试试，或者清空搜索条件。"
                                                       title:@"No Matching Files"];
        [self.webView loadHTMLString:html baseURL:nil];
    }
}

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item {
    FileNode *node = item ?: self.rootNode;
    return node.children.count;
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item {
    FileNode *node = item ?: self.rootNode;
    return node.children[(NSUInteger)index];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item {
    FileNode *node = item;
    return node.directory;
}

- (nullable NSView *)outlineView:(NSOutlineView *)outlineView
              viewForTableColumn:(nullable NSTableColumn *)tableColumn
                            item:(id)item {
    NSTableCellView *cell = [outlineView makeViewWithIdentifier:@"Cell" owner:self];
    if (cell == nil) {
        cell = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, tableColumn.width, 28)];
        NSTextField *textField = [[NSTextField alloc] initWithFrame:NSMakeRect(6, 4, tableColumn.width - 10, 20)];
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

    FileNode *node = item;
    cell.textField.stringValue = node.name;
    cell.textField.font = node.directory ? [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold] : [NSFont systemFontOfSize:13];
    return cell;
}

- (BOOL)outlineView:(NSOutlineView *)outlineView shouldSelectItem:(id)item {
    FileNode *node = item;
    return !node.directory;
}

- (void)outlineViewSelectionDidChange:(NSNotification *)notification {
    id item = [self.outlineView itemAtRow:self.outlineView.selectedRow];
    if (![item isKindOfClass:[FileNode class]]) {
        return;
    }

    FileNode *node = item;
    if (!node.directory) {
        [self showMarkdownAtURL:node.fileURL];
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
