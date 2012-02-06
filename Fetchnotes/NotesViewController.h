//
//  NotesViewController.h
//  Fetchnotes
//
// Common Public Attribution License Version 1.0. 
// “The contents of this file are subject to the Common Public Attribution 
// License Version 1.0 (the “License”); you may not use this file except in 
// compliance with the License. You may obtain a copy of the License at 
// http://www.fetchnotes.com/license. The License is based on the Mozilla 
// Public License Version 1.1 but Sections 14 and 15 have been added to cover 
// use of software over a computer network and provide for limited attribution 
// for the Original Developer. In addition, Exhibit A has been modified to be 
// consistent with Exhibit B. 
// Software distributed under the License is distributed on an “AS IS” basis, 
// WITHOUT WARRANTY OF ANY KIND, either express or implied. See the License for 
// the specific language governing rights and limitations under the License. 
// The Original Code is Fetchnotes. 
// The Original Developer is the Initial Developer. 
// The Initial Developer of the Original Code is Fetchnotes LLC. All portions 
// of the code written by Fetchnotes LLC are Copyright (c) 2011 Fetchnotes LLC. 
// All Rights Reserved. 

#import <UIKit/UIKit.h>
#import <sqlite3.h>
@class NoteDetailViewController;
@class SettingsViewController;

@interface NotesViewController : UIViewController <UITableViewDelegate, UITableViewDataSource, UISearchBarDelegate>
{
    NoteDetailViewController *_detailViewController;
    UINavigationController  *_settingsNavBarController;
    SettingsViewController  *_settingsViewController;
    IBOutlet UITableView    *_noteTableView;
    IBOutlet UIScrollView   *_tagsFilterView;
    IBOutlet UISearchBar    *_mySearchBar;
    
    NSMutableArray  *_notes;
    NSMutableArray  *_filteredNotes;
    NSMutableArray  *_tags;
    NSMutableArray  *_selectedTags;
    
    NSMutableDictionary    *_buttonsDictionary;
    
    sqlite3         *_database;
    NSString        *_publicKey;
    NSString        *_privateKey;
    NSString        *_author;
    NSString        *_email;
    NSString        *_updateTime;
    
    UIActivityIndicatorView *_loadingIndicator;	
    NSTimer         *_refreshTimer;
    
    UIBarButtonItem *_filterViewControlButton;
    BOOL            _isFiltering; // the notes displayed are not all notes
    BOOL            _filterIsUp;
    double          _yFilterUp;
    
    BOOL            _loggedInOnAppStart; // only useful on the start, not used after this
    
}

@property (nonatomic, retain) NSString        *publicKey;
@property (nonatomic, retain) NSString        *privateKey;
@property (nonatomic, retain) NSString        *author;
@property (nonatomic, retain) NSString        *email;
@property (nonatomic, retain) NSString        *updateTime;


- (id)initWithDatabase:(sqlite3 *)database;
- (BOOL)checkIfUserExists;

@end
