//
//  LogExportsTableViewController.h
//
//  Copyright (C) 2017 IRCCloud, Ltd.
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.

#import "LogExportsTableViewController.h"
#import "NetworkConnection.h"
#import "UIColor+IRCCloud.h"

@implementation LogExportsTableViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    _downloaded = [[NSMutableArray alloc] init];
    _downloadingURLs = [[NSMutableDictionary alloc] init];
    _iCloudLogs = [[UISwitch alloc] init];
    [_iCloudLogs addTarget:self action:@selector(iCloudLogsChanged:) forControlEvents:UIControlEventValueChanged];
    self.navigationItem.title = @"Download Logs";
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(doneButtonPressed:)];
}

-(void)doneButtonPressed:(id)sender {
    [self dismissViewControllerAnimated:YES completion:nil];
}

-(void)iCloudLogsChanged:(id)sender {
    BOOL on = _iCloudLogs.on;
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        @synchronized(self) {
            [[NSUserDefaults standardUserDefaults] setBool:on forKey:@"iCloudLogs"];
            
            NSFileManager *fm = [NSFileManager defaultManager];
            NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
            NSURL *iCloudPath = [[fm URLForUbiquityContainerIdentifier:nil] URLByAppendingPathComponent:@"Documents"];
            NSURL *localPath = [[fm URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] objectAtIndex:0];
            
            NSURL *source,*dest;
            
            if(on) {
                source = localPath;
                dest = iCloudPath;
            } else {
                source = iCloudPath;
                dest = localPath;
            }
            
            for(NSURL *file in [fm contentsOfDirectoryAtURL:source includingPropertiesForKeys:nil options:0 error:nil]) {
                [coordinator coordinateReadingItemAtURL:file options:0 writingItemAtURL:[dest URLByAppendingPathComponent:file.lastPathComponent] options:NSFileCoordinatorWritingForReplacing error:nil byAccessor:^(NSURL *newReadingURL, NSURL *newWritingURL) {
                    CLS_LOG(@"Moving %@ to %@", newReadingURL, newWritingURL);
                    NSError *error;
                    [fm removeItemAtURL:[dest URLByAppendingPathComponent:file.lastPathComponent] error:nil];
                    [fm setUbiquitous:on itemAtURL:newReadingURL destinationURL:newWritingURL error:&error];
                    if(error)
                        CLS_LOG(@"Error moving file: %@", error);
                }];
            }
        }
    });
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

-(void)refresh:(NSDictionary *)logs {
    [_downloaded removeAllObjects];
    _inprogress = [logs objectForKey:@"inprogress"];
    NSMutableArray *available = [[logs objectForKey:@"available"] mutableCopy];
    NSMutableArray *expired = [[logs objectForKey:@"expired"] mutableCopy];
    
    for(int i = 0; i < available.count; i++) {
        NSDictionary *d = [available objectAtIndex:i];
        if([self downloadExists:d]) {
            [_downloaded addObject:d];
            [available removeObject:d];
            i--;
        }
    }
    
    for(int i = 0; i < expired.count; i++) {
        NSDictionary *d = [expired objectAtIndex:i];
        if([self downloadExists:d]) {
            [_downloaded addObject:d];
            [expired removeObject:d];
            i--;
        }
    }
    
    _available = available;
    _expired = expired;
    
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        [self.tableView reloadData];
    }];
}

-(void)refresh {
    @synchronized(self) {
        NSMutableDictionary *logs = [[NetworkConnection sharedInstance] getLogExports].mutableCopy;
        [logs removeObjectForKey:@"timezones"];
        [[NSUserDefaults standardUserDefaults] setObject:[NSKeyedArchiver archivedDataWithRootObject:logs] forKey:@"logs_cache"];
        
        [self refresh:logs];
    }
}

-(void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    _iCloudLogs.on = [[NSUserDefaults standardUserDefaults] boolForKey:@"iCloudLogs"];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleEvent:) name:kIRCCloudEventNotification object:nil];
    if([[NSUserDefaults standardUserDefaults] objectForKey:@"logs_cache"])
        [self refresh:[NSKeyedUnarchiver unarchiveObjectWithData:[[NSUserDefaults standardUserDefaults] objectForKey:@"logs_cache"]]];
    [self performSelectorInBackground:@selector(refresh) withObject:nil];
}

-(void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

-(void)handleEvent:(NSNotification *)notification {
    kIRCEvent event = [[notification.userInfo objectForKey:kIRCCloudEventKey] intValue];
    
    switch(event) {
        case kIRCEventLogExportFinished:
            [self performSelectorInBackground:@selector(refresh) withObject:nil];
            break;
        default:
            break;
    }
}

#pragma mark - Table view data source

-(UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0,0,self.view.frame.size.width,24)];
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(16,0,self.view.frame.size.width - 32, 20)];
    label.text = [self tableView:tableView titleForHeaderInSection:section].uppercaseString;
    label.font = [UIFont systemFontOfSize:14];
    label.textColor = [UILabel appearanceWhenContainedIn:[UITableViewHeaderFooterView class], nil].textColor;
    label.autoresizingMask = UIViewAutoresizingFlexibleTopMargin;
    [header addSubview:label];
    return header;
}

-(CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return 48;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1 + (_inprogress.count > 0) + (_downloaded.count > 0) + (_available.count > 0) + (_expired.count > 0);
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if(section > 0 && _inprogress.count == 0)
        section++;
    
    if(section > 1 && _downloaded.count == 0)
        section++;

    if(section > 2 && _available.count == 0)
        section++;
    
    switch(section) {
        case 0:
            return [[NSFileManager defaultManager] ubiquityIdentityToken]?4:3;
        case 1:
            return _inprogress.count;
        case 2:
            return _downloaded.count;
        case 3:
            return _available.count;
        case 4:
            return _expired.count;
    }
    return 0;
}

-(NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if(section > 0 && _inprogress.count == 0)
        section++;
    
    if(section > 1 && _downloaded.count == 0)
        section++;

    if(section > 2 && _available.count == 0)
        section++;
    
    switch(section) {
        case 0:
            return @"Export Logs";
        case 1:
            return @"Pending Downloads";
        case 2:
            return @"Downloaded";
        case 3:
            return @"Available Downloads";
        case 4:
            return @"Expired Downloads";
    }
    return nil;
}

-(CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if(indexPath.section == 0)
        return 44;
    else
        return 64;
}

- (NSString *)relativeTime:(double)seconds {
    NSString *date = nil;
    seconds = fabs(seconds);
    double minutes = fabs(seconds) / 60.0;
    double hours = minutes / 60.0;
    double days = hours / 24.0;
    double months = days / 31.0;
    double years = months / 12.0;
    
    if(years >= 1) {
        if(years - (int)years > 0.5)
            years++;
        
        if((int)years == 1)
            date = [NSString stringWithFormat:@"%i year", (int)years];
        else
            date = [NSString stringWithFormat:@"%i years", (int)years];
    } else if(months >= 1) {
        if(months - (int)months > 0.5)
            months++;
        
        if((int)months == 1)
            date = [NSString stringWithFormat:@"%i month", (int)months];
        else
            date = [NSString stringWithFormat:@"%i months", (int)months];
    } else if(days >= 1) {
        if(days - (int)days > 0.5)
            days++;
        
        if((int)days == 1)
            date = [NSString stringWithFormat:@"%i day", (int)days];
        else
            date = [NSString stringWithFormat:@"%i days", (int)days];
    } else if(hours >= 1) {
        if(hours - (int)hours > 0.5)
            hours++;
        
        if((int)hours < 2)
            date = [NSString stringWithFormat:@"%i hour", (int)hours];
        else
            date = [NSString stringWithFormat:@"%i hours", (int)hours];
    } else if(minutes >= 1) {
        if(minutes - (int)minutes > 0.5)
            minutes++;
        
        if((int)minutes == 1)
            date = [NSString stringWithFormat:@"%i minute", (int)minutes];
        else
            date = [NSString stringWithFormat:@"%i minutes", (int)minutes];
    } else {
        if((int)seconds == 1)
            date = [NSString stringWithFormat:@"%i second", (int)seconds];
        else
            date = [NSString stringWithFormat:@"%i seconds", (int)seconds];
    }
    return date;
}

- (BOOL)downloadExists:(NSDictionary *)row {
    if([row objectForKey:@"file_name"] && ![[row objectForKey:@"file_name"] isKindOfClass:[NSNull class]]) {
        return ([[NSFileManager defaultManager] fileExistsAtPath:[[self downloadsPath] URLByAppendingPathComponent:[row objectForKey:@"file_name"]].path]);
    } else {
        return NO;
    }
}

- (NSURL *)fileForDownload:(NSDictionary *)row {
    return [[self downloadsPath] URLByAppendingPathComponent:[row objectForKey:@"file_name"]];
}

- (NSURL *)downloadsPath {
    NSFileManager *fm = [NSFileManager defaultManager];
    if([fm ubiquityIdentityToken] && [[NSUserDefaults standardUserDefaults] boolForKey:@"iCloudLogs"])
        return [[fm URLForUbiquityContainerIdentifier:nil] URLByAppendingPathComponent:@"Documents"];
    else
        return [[fm URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] objectAtIndex:0];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"LogExport"];
    if(!cell)
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"LogExport"];
    
    cell.accessoryView = nil;
    
    if(indexPath.section == 0) {
        switch(indexPath.row) {
            case 0:
                cell.textLabel.text = @"This Network";
                cell.detailTextLabel.text = _server.name.length ? _server.name : _server.hostname;
                break;
            case 1:
                cell.textLabel.text = @"This Channel";
                cell.detailTextLabel.text = _buffer.name;
                break;
            case 2:
                cell.textLabel.text = @"All Networks";
                cell.detailTextLabel.text = [NSString stringWithFormat:@"%lu networks", (unsigned long)[ServersDataSource sharedInstance].count];
                break;
            case 3:
                cell.textLabel.text = @"Store Logs on iCloud Drive";
                cell.detailTextLabel.text = nil;
                cell.accessoryView = _iCloudLogs;
                break;
        }
        cell.accessoryType = UITableViewCellAccessoryNone;
    } else {
        NSInteger section = indexPath.section;
        
        if(section > 0 && _inprogress.count == 0)
            section++;
        
        if(section > 1 && _downloaded.count == 0)
            section++;

        if(section > 2 && _available.count == 0)
            section++;
        
        UIActivityIndicatorView *spinner;
        NSDictionary *row = nil;
        switch(section) {
            case 1:
                row = [_inprogress objectAtIndex:indexPath.row];
                cell.accessoryType = UITableViewCellAccessoryNone;
                spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:[UIColor activityIndicatorViewStyle]];
                [spinner sizeToFit];
                [spinner startAnimating];
                cell.accessoryView = spinner;
                break;
            case 2:
                row = [_downloaded objectAtIndex:indexPath.row];
                cell.accessoryType = UITableViewCellAccessoryNone;
                break;
            case 3:
                row = [_available objectAtIndex:indexPath.row];
                if([_downloadingURLs objectForKey:[row objectForKey:@"redirect_url"]]) {
                    cell.accessoryType = UITableViewCellAccessoryNone;
                    spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:[UIColor activityIndicatorViewStyle]];
                    [spinner sizeToFit];
                    [spinner startAnimating];
                    cell.accessoryView = spinner;
                } else {
                    cell.accessoryType = UITableViewCellAccessoryNone;
                }
                break;
            case 4:
                row = [_expired objectAtIndex:indexPath.row];
                cell.accessoryType = UITableViewCellAccessoryNone;
                break;
        }
        Server *s = ![[row objectForKey:@"cid"] isKindOfClass:[NSNull class]] ? [[ServersDataSource sharedInstance] getServer:[[row objectForKey:@"cid"] intValue]] : nil;
        Buffer *b = ![[row objectForKey:@"bid"] isKindOfClass:[NSNull class]] ? [[BuffersDataSource sharedInstance] getBuffer:[[row objectForKey:@"bid"] intValue]] : nil;
        
        NSString *serverName = s ? (s.name.length ? s.name : s.hostname) : [NSString stringWithFormat:@"Unknown Network (%@)", [row objectForKey:@"cid"]];
        NSString *bufferName = b ? b.name : [NSString stringWithFormat:@"Unknown Log (%@)", [row objectForKey:@"bid"]];
        
        if(![[row objectForKey:@"bid"] isKindOfClass:[NSNull class]])
            cell.textLabel.text = [NSString stringWithFormat:@"%@: %@", serverName, bufferName];
        else if(![[row objectForKey:@"cid"] isKindOfClass:[NSNull class]])
            cell.textLabel.text = serverName;
        else
            cell.textLabel.text = @"All Networks";

        if(section == 2 || [[row objectForKey:@"expirydate"] isKindOfClass:[NSNull class]])
            cell.detailTextLabel.text = [NSString stringWithFormat:@"Exported %@ ago", [self relativeTime:[NSDate date].timeIntervalSince1970 - [[row objectForKey:@"startdate"] doubleValue]]];
        else
            cell.detailTextLabel.text = [NSString stringWithFormat:([NSDate date].timeIntervalSince1970 - [[row objectForKey:@"expirydate"] doubleValue] < 0)?@"Exported %@ ago\nExpires in %@":@"Exported %@ ago\nExpired %@ ago", [self relativeTime:[NSDate date].timeIntervalSince1970 - [[row objectForKey:@"startdate"] doubleValue]], [self relativeTime:[NSDate date].timeIntervalSince1970 - [[row objectForKey:@"expirydate"] doubleValue]]];
        cell.detailTextLabel.numberOfLines = 0;
    }
    
    return cell;
}

#pragma mark - Table view delegate

-(void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:NO];
    
    NSInteger section = indexPath.section;
    
    if(section > 0 && _inprogress.count == 0)
        section++;
    
    if(section > 1 && _downloaded.count == 0)
        section++;
    
    if(section > 2 && _available.count == 0)
        section++;
    
    IRCCloudAPIResultHandler exportHandler = ^(IRCCloudJSONObject *result) {
        if([[result objectForKey:@"success"] boolValue]) {
            NSMutableArray *inprogress = _inprogress.mutableCopy;
            [inprogress insertObject:[result objectForKey:@"export"] atIndex:0];
            _inprogress = inprogress;
            [self.tableView reloadData];
            [[[UIAlertView alloc] initWithTitle:@"Exporting" message:@"Your log export is in progress.  We'll email you when it's ready." delegate:nil cancelButtonTitle:@"Close" otherButtonTitles:nil] show];
        } else {
            [[[UIAlertView alloc] initWithTitle:@"Export Failed" message:[NSString stringWithFormat:@"Unable to export log: %@.  Please try again shortly.", [result objectForKey:@"message"]] delegate:nil cancelButtonTitle:@"Close" otherButtonTitles:nil] show];
        }
    };
    
    switch(section) {
        case 0:
            switch(indexPath.row) {
                case 0:
                    [[NetworkConnection sharedInstance] exportLog:[NSTimeZone localTimeZone].name cid:_server.cid bid:-1 handler:exportHandler];
                    break;
                case 1:
                    [[NetworkConnection sharedInstance] exportLog:[NSTimeZone localTimeZone].name cid:_server.cid bid:_buffer.bid handler:exportHandler];
                    break;
                case 2:
                    [[NetworkConnection sharedInstance] exportLog:[NSTimeZone localTimeZone].name cid:-1 bid:-1 handler:exportHandler];
                    break;
            }
            break;
        case 1:
            [[[UIAlertView alloc] initWithTitle:@"Preparing Download" message:@"This export is being prepared.  You will recieve a notification when it is ready for download." delegate:nil cancelButtonTitle:@"Close" otherButtonTitles:nil] show];
            break;
        case 2:
        {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleActionSheet];
            [alert addAction:[UIAlertAction actionWithTitle:@"Open" style:UIAlertActionStyleDefault handler:^(UIAlertAction *alert) {
                [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                    _interactionController = [UIDocumentInteractionController interactionControllerWithURL:[self fileForDownload:[_downloaded objectAtIndex:indexPath.row]]];
                    [_interactionController presentOpenInMenuFromRect:[self.view convertRect:[self.tableView rectForRowAtIndexPath:indexPath] fromView:self.tableView] inView:self.view animated:YES];
                }];
            }]];
            
            [alert addAction:[UIAlertAction actionWithTitle:@"Delete" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *alert) {
                NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
                [coordinator coordinateWritingItemAtURL:[self fileForDownload:[_downloaded objectAtIndex:indexPath.row]] options:NSFileCoordinatorWritingForDeleting error:nil byAccessor:^(NSURL *writingURL) {
                    NSError *error;
                    [[NSFileManager defaultManager] removeItemAtPath:writingURL.path error:NULL];
                    if(error)
                        NSLog(@"Error: %@", error);
                    [self performSelectorInBackground:@selector(refresh) withObject:nil];
                }];
                [self.tableView reloadData];
            }]];

            [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
            alert.popoverPresentationController.sourceRect = [self.tableView rectForRowAtIndexPath:indexPath];
            alert.popoverPresentationController.sourceView = self.tableView;
            [self presentViewController:alert animated:YES completion:nil];
            break;
        }
        case 3:
            [self download:[NSURL URLWithString:[[_available objectAtIndex:indexPath.row] objectForKey:@"redirect_url"]]];
            break;
    }
}

-(void)download:(NSURL *)url {
    NSURLSession *session;
    NSURLSessionConfiguration *config;
    config = [NSURLSessionConfiguration backgroundSessionConfigurationWithIdentifier:[NSString stringWithFormat:@"com.irccloud.logs.%li", time(NULL)]];
#ifdef ENTERPRISE
    config.sharedContainerIdentifier = @"group.com.irccloud.enterprise.share";
#else
    config.sharedContainerIdentifier = @"group.com.irccloud.share";
#endif
    config.HTTPCookieStorage = nil;
    config.URLCache = nil;
    config.requestCachePolicy = NSURLCacheStorageNotAllowed;
    config.discretionary = NO;
    session = [NSURLSession sessionWithConfiguration:config delegate:self delegateQueue:[NSOperationQueue mainQueue]];
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:30];
    [request setHTTPShouldHandleCookies:NO];
    [request setValue:[NSString stringWithFormat:@"session=%@",[NetworkConnection sharedInstance].session] forHTTPHeaderField:@"Cookie"];
    
    [[session downloadTaskWithRequest:request] resume];

    [_downloadingURLs setObject:@(YES) forKey:url.absoluteString];
    [self.tableView reloadData];
}

-(void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    [_downloadingURLs removeObjectForKey:task.originalRequest.URL.absoluteString];
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        [self.tableView reloadData];
        UILocalNotification *alert = [[UILocalNotification alloc] init];
        alert.fireDate = [NSDate date];
        alert.soundName = @"a.caf";
        if(error) {
            alert.alertTitle = @"Download Failed";
            alert.alertBody = [NSString stringWithFormat:@"Unable to download logs: %@", error.description];
        } else {
            alert.alertTitle = @"Download Complete";
            alert.alertBody = @"Logs are now available";
            alert.category = @"view_logs";
            alert.userInfo = @{@"view_logs":@(YES)};
        }
        [[UIApplication sharedApplication] scheduleLocalNotification:alert];
        if(self.completionHandler)
            self.completionHandler();
    }];
}

-(void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didFinishDownloadingToURL:(NSURL *)location {
    NSError *error;
    NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
    NSFileManager *fm = [NSFileManager defaultManager];
    
    NSURL *dest = [self downloadsPath];
    [coordinator coordinateWritingItemAtURL:dest options:0 error:&error byAccessor:^(NSURL *newURL) {
        [fm createDirectoryAtURL:dest withIntermediateDirectories:YES attributes:nil error:NULL];
    }];
    
    dest = [dest URLByAppendingPathComponent:downloadTask.originalRequest.URL.lastPathComponent];
    
    [coordinator coordinateReadingItemAtURL:location options:0 writingItemAtURL:dest options:NSFileCoordinatorWritingForReplacing error:&error byAccessor:^(NSURL *newReadingURL, NSURL *newWritingURL) {
        NSError *error;
        [fm removeItemAtPath:newWritingURL.path error:NULL];
        [fm copyItemAtPath:newReadingURL.path toPath:newWritingURL.path error:&error];
        if(error)
            NSLog(@"Error: %@", error);
    }];
    
    [_downloadingURLs removeObjectForKey:downloadTask.originalRequest.URL];
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        NSMutableArray *available = _available.mutableCopy;
        
        for(int i = 0; i < available.count; i++) {
            if([[[available objectAtIndex:i] objectForKey:@"redirect_url"] isEqualToString:downloadTask.originalRequest.URL.absoluteString]) {
                [_downloaded addObject:[available objectAtIndex:i]];
                [available removeObjectAtIndex:i];
                break;
            }
        }
        
        _available = available;
        
        [self.tableView reloadData];

        if(self.completionHandler)
            self.completionHandler();
    }];
}
@end