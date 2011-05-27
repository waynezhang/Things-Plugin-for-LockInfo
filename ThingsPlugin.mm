#import <UIKit/UIKit.h>
#import <SpringBoard/SpringBoard.h>
#import <objc/runtime.h>
#import <sqlite3.h>

#import "ThingsPlugin.h"

extern "C" CFStringRef UIDateFormatStringForFormatType(CFStringRef type);

#define TITLE_LABEL_TAG         328 
#define TODO_TITLE_LABEL_TAG    329
#define TODO_DUE_LABEL_TAG      330

// plugin
@interface ThingsPlugin (Private)

- (void)update;
- (void)updateTodo;
- (void)updatePreference;

- (UITableViewCell *)tableView:(LITableView *)tableView cellWithTitle:(NSString *)title;
- (UITableViewCell *)tableView:(LITableView *)tableView cellWithTodo:(NSArray *)todo;

@end

@implementation ThingsPlugin

@synthesize plugin, databasePath, todoList, showNext, showDue, dueSeconds;

- (id)initWithPlugin:(LIPlugin*)thePlugin
{
  self = [super init];
  self.plugin = thePlugin;

  self.todoList = [NSMutableArray array];

  plugin.tableViewDataSource = self;
  plugin.tableViewDelegate = self;

  // get things path
  SBApplication* thingsApp = [[objc_getClass("SBApplicationController") sharedInstance] applicationWithDisplayIdentifier:@"com.culturedcode.ThingsTouch"];
  NSString *thingsPath = [[thingsApp path] stringByDeletingLastPathComponent];
  self.databasePath = [[thingsPath stringByAppendingPathComponent:@"Documents"] stringByAppendingPathComponent:(@"db.sqlite3")];

  // notification
  NSNotificationCenter* center = [NSNotificationCenter defaultCenter];
  [center addObserver:self selector:@selector(update) name:LITimerNotification object:nil];
  [center addObserver:self selector:@selector(update) name:LIPrefsUpdatedNotification object:nil];
  [center addObserver:self selector:@selector(update) name:LIViewReadyNotification object:nil];

  return self;
}

- (void)dealloc
{
  self.plugin = nil;
  self.todoList = nil;
  self.databasePath = nil;

  [super dealloc];
}

#pragma mark UITableViewDataSource
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section 
{
  return [self.todoList count];
}

- (UITableViewCell *)tableView:(LITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath 
{
  id object = [self.todoList objectAtIndex:indexPath.row];

  UITableViewCell *cell = nil;
  if ([object isKindOfClass:[NSString class]]) {
    cell = [self tableView:tableView cellWithTitle:object];
  } else {
    cell = [self tableView:tableView cellWithTodo:object];
  }

  return cell;
}

- (CGFloat)tableView:(LITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
  id object = [self.todoList objectAtIndex:indexPath.row];

  if ([object isKindOfClass:[NSString class]]) {
    // title
    return 20;
  } else {
    return 35;
  }
}

- (UITableViewCell *)tableView:(LITableView *)tableView cellWithTitle:(NSString *)title
{
  NSString *reuseId = @"TitleCell";
  UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuseId];
  if (cell == nil) {
      cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseId] autorelease];

      LILabel *titleLabel = [tableView labelWithFrame:CGRectMake(0, 0, 320, 20)];
      titleLabel.style = tableView.theme.summaryStyle;
      titleLabel.numberOfLines = 1;
      titleLabel.backgroundColor = [UIColor clearColor];
      titleLabel.textAlignment = UITextAlignmentCenter;

      titleLabel.tag = TITLE_LABEL_TAG;
      [cell.contentView addSubview:titleLabel];
  }

  LILabel *titleLabel = [cell.contentView viewWithTag:TITLE_LABEL_TAG];
  titleLabel.text = title;

  return cell;
}

- (UITableViewCell *)tableView:(LITableView *)tableView cellWithTodo:(NSArray *)todo
{
  NSString *reuseId = @"TodoCell";
  UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuseId];
  if (cell == nil) {
      cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseId] autorelease];

      // padding-y 3, 15, 14, 3
      CGRect titleLabelFrame = CGRectMake(15, 3, 290, 15);
      CGRect detailLabelFrame = CGRectMake(15, 18, 290, 14);

      LILabel *titleLabel = [tableView labelWithFrame:titleLabelFrame];
      titleLabel.backgroundColor = [UIColor clearColor];
      titleLabel.style = tableView.theme.summaryStyle;
      titleLabel.tag = TODO_TITLE_LABEL_TAG;
      [cell.contentView addSubview:titleLabel];

      LILabel *detailLabel = [tableView labelWithFrame:detailLabelFrame];
      detailLabel.backgroundColor = [UIColor clearColor];
      detailLabel.style = tableView.theme.detailStyle;
      detailLabel.tag = TODO_DUE_LABEL_TAG;
      [cell.contentView addSubview:detailLabel];
  }

  LILabel *titleLabel = [cell.contentView viewWithTag:TODO_TITLE_LABEL_TAG];
  titleLabel.text = (NSString *) [todo objectAtIndex:0];

  LILabel *detailLabel = [cell.contentView viewWithTag:TODO_DUE_LABEL_TAG];
  double due = [((NSNumber *) [todo objectAtIndex:1]) doubleValue];
  if (due == 0) {
    detailLabel.text = @"No due date";
  } else {
    NSDate *date = [NSDate dateWithTimeIntervalSinceReferenceDate:due];
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = (NSString*)UIDateFormatStringForFormatType(CFSTR("UIWeekdayNoYearDateFormat"));
    detailLabel.text = [formatter stringFromDate:date];
    [formatter release];
  }

  return cell;
}


- (void)update
{
  if (!self.plugin.enabled) {
    return;
  }

  NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
  [self updatePreference];
  [self updateTodo];
  [pool release];
}

- (void)updateTodo
{
  int ret;

  [self.todoList removeAllObjects];

  sqlite3 *database = NULL;
  @try {
    ret = sqlite3_open([self.databasePath UTF8String], &database);
    if (ret != SQLITE_OK) {
      NSLog(@"TP: sqlite3_open ret %d", ret);
      return;
    }

    // today
    sqlite3_stmt *statement = NULL;
    @try {
      NSString *sqlForToday = @"SELECT title, duedate FROM Task WHERE type = 2 AND status = 1 AND (flagged = 1 OR focus = 1) ORDER BY duedate, touchedDate";
      ret = (sqlite3_prepare_v2 (database, [sqlForToday UTF8String], -1, &statement, NULL) != SQLITE_OK) ;
      if (ret != SQLITE_OK) {
        NSLog(@"TP: prepare failed %d", ret);
        return;
      }

      NSLog(@"LI: ThingsPlugin Inbox/Today sql: %@", sqlForToday);

      BOOL titleAdded = NO;
      while (sqlite3_step (statement) == SQLITE_ROW) {
        if (!titleAdded) {
          [todoList addObject:@"Inbox / Today"];
          titleAdded = YES;
        }

        const char *titlePtr = (const char*) sqlite3_column_text (statement, 0);
        double due  = sqlite3_column_double (statement, 1);

        NSString *title = [NSString stringWithUTF8String:(titlePtr == NULL ? "" : titlePtr)];
        NSArray *todo = [NSArray arrayWithObjects:title, [NSNumber numberWithDouble:due], nil];
        [todoList addObject:todo];
      }
    }
    @finally {
      if (statement != NULL) {
        sqlite3_finalize(statement);
        statement = NULL;
      }
    }

    // next
    if (self.showNext) {
      @try {
        NSString *sqlForNext = @"SELECT title, duedate FROM Task WHERE type = 2 AND status = 1 AND flagged = 0 AND focus = 2 ORDER BY duedate, touchedDate";
        ret = (sqlite3_prepare_v2 (database, [sqlForNext UTF8String], -1, &statement, NULL) != SQLITE_OK);
        if (ret != SQLITE_OK) {
          NSLog(@"TP: prepare failed %d", ret);
          return;
        }

        NSLog(@"LI: ThingsPlugin next sql: %@", sqlForNext);

        BOOL titleAdded = NO;
        while (sqlite3_step (statement) == SQLITE_ROW) {
          if (!titleAdded) {
            [todoList addObject:@"Next"];
            titleAdded = YES;
          }

          const char *titlePtr = (const char*) sqlite3_column_text (statement, 0);
          double due  = sqlite3_column_double (statement, 1);

          NSString *title = [NSString stringWithUTF8String:(titlePtr == NULL ? "" : titlePtr)];
          NSArray *todo = [NSArray arrayWithObjects:title, [NSNumber numberWithDouble:due], nil];
          [todoList addObject:todo];
        }
      }
      @finally {
        if (statement != NULL) {
          sqlite3_finalize(statement);
        }
      }
    }

    // due
    if (self.showDue) {
      @try {
        NSString *sqlForDue = @"SELECT title, duedate FROM Task WHERE type = 2 AND status = 1 AND flagged = 0 AND focus = 8 AND uuid NOT IN (SELECT substr(uuid, 1, 36) from Task WHERE focus != 8 AND status = 1 AND type = 2)";
        if (self.dueSeconds > 0) {
          double time = [NSDate timeIntervalSinceReferenceDate] + self.dueSeconds;
          sqlForDue = [NSString stringWithFormat:@"%@ AND duedate < %f", sqlForDue, time];
        }
        sqlForDue = [NSString stringWithFormat:@"%@ %@", sqlForDue, @"ORDER BY duedate, touchedDate"];
        ret = (sqlite3_prepare_v2 (database, [sqlForDue UTF8String], -1, &statement, NULL) != SQLITE_OK);
        if (ret != SQLITE_OK) {
          NSLog(@"TP: prepare failed %d", ret);
          return;
        }

        NSLog(@"LI: ThingsPlugin due sql: %@", sqlForDue);

        BOOL titleAdded = NO;
        while (sqlite3_step (statement) == SQLITE_ROW) {
          if (!titleAdded) {
            [todoList addObject:@"Due"];
            titleAdded = YES;
          }

          const char *titlePtr = (const char*) sqlite3_column_text (statement, 0);
          double due  = sqlite3_column_double (statement, 1);

          NSString *title = [NSString stringWithUTF8String:(titlePtr == NULL ? "" : titlePtr)];
          NSArray *todo = [NSArray arrayWithObjects:title, [NSNumber numberWithDouble:due], nil];
          [todoList addObject:todo];
        }
      }
      @finally {
        if (statement != NULL) {
          sqlite3_finalize(statement);
        }
      }
    }
  }
  @finally {
    if (database != NULL) {
      sqlite3_close(database);
    }
  }


  [[NSNotificationCenter defaultCenter] postNotificationName:LIUpdateViewNotification object:self.plugin userInfo:nil];
}

- (void)updatePreference
{
  NSNumber *value = nil;
  
  value = [self.plugin.preferences valueForKey:@"ShowNext"];
  self.showNext = [value boolValue];

  value = [self.plugin.preferences valueForKey:@"DueInDays"];
  switch ([value intValue]) {
    case -1:
      self.showDue = NO;
      self.dueSeconds = -1;
      break;
    case 999:
      self.showDue = YES;
      self.dueSeconds = -1;
      break;
    default:
      self.showDue = YES;
      self.dueSeconds = [value intValue] * (1 * 60 * 60 * 24);
      break;
  }
}

@end
