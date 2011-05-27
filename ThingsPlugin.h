#import <Foundation/Foundation.h>
#include "Plugin.h"

@interface ThingsPlugin : NSObject <LIPluginController, LITableViewDelegate, UITableViewDataSource> 
{

}

@property (nonatomic, retain) LIPlugin *plugin;
@property (nonatomic, retain) NSString *databasePath;
@property (nonatomic, retain) NSMutableArray *todoList;
@property (nonatomic, assign) BOOL showNext;
@property (nonatomic, assign) BOOL showDue;
@property (nonatomic, assign) double dueSeconds;

@end
