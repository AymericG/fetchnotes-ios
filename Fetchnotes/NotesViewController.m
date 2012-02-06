//
//  NotesViewController.m
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

#include <CommonCrypto/CommonDigest.h>
#import <QuartzCore/QuartzCore.h>
#import "TransparentToolbar.h"
#import "SBJson.h"
#import "ASIFormDataRequest.h"

#import "NotesViewController.h"
#import "NoteDetailViewController.h"
#import "Constants.h"
#import "Note.h"
#import "NoteCell.h"
#import "SettingsViewController.h"

static UIImage *greyImage = nil;
static UIImage *whiteImage = nil;

static sqlite3_stmt *load_notes_stmt = nil;
static sqlite3_stmt *load_tags_stmt = nil;
static sqlite3_stmt *update_note_text_statment = nil;
static sqlite3_stmt *delete_note_statement = nil;
static sqlite3_stmt *delete_tag_statement = nil;
static sqlite3_stmt *count_paired_tag_statement = nil;
static sqlite3_stmt *delete_pair_statement = nil;
static sqlite3_stmt *insert_note_statement = nil;
static sqlite3_stmt *insert_pair_statement = nil;
static sqlite3_stmt *insert_tag_statement = nil;
static sqlite3_stmt *mark_delete_note_stmt = nil;

static sqlite3_stmt *sync_load_user_info_stmt = nil;
static sqlite3_stmt *sync_empty_svid_local_stmt = nil;
static sqlite3_stmt *sync_deleted_local_stmt = nil;
static sqlite3_stmt *sync_update_svid_mtime_local_stmt = nil;
static sqlite3_stmt *sync_svid_exist_local_stmt = nil;
static sqlite3_stmt *sync_change_update_time_local_stmt = nil;
static sqlite3_stmt *sync_delete_note_stmt = nil;
static sqlite3_stmt *sync_reset_delete_bit_stmt = nil;
static sqlite3_stmt *sync_load_synctime_stmt = nil;
static sqlite3_stmt *sync_load_modified_notes_stmt = nil;

@interface NotesViewController (Private) 
- (void)deleteNoteWithID:(int)pk;
- (void)filterTags;
- (void)showSettingsOrAllNotesButton;
- (void)showAllNotes;
- (void)loadAllNotes;
- (void)arrangeButtons;
- (void)deleteNoteWithSvid:(NSString *)svid;
- (void)deleteOldPairAndTag:(NSString *)oldtag withNoteID:(int)pk;
- (void)saveNewTagAndPair:(NSString *)tag noteID:(int)pk; 
- (void)addNewNote:(Note *)note;
- (void)filterViewUp;
- (void)startSynchronize:(NSNotification *)notif;
- (void)loadAllTags;
@end

@implementation NotesViewController
@synthesize author = _author;
@synthesize email = _email;
@synthesize privateKey = _privateKey;
@synthesize publicKey = _publicKey;
@synthesize updateTime = _updateTime;


- (void)DisplayAlert:(NSString *)title andMessage:(NSString *)message 
{
	UIAlertView* alert = [[UIAlertView alloc] initWithTitle:title message:message delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
	[alert show];
	[alert release];
}

#pragma mark syncing

// output format: 2012-01-01T01:23:45.678901
- (NSString *)formatDatetimeToServer:(NSString *)time
{
    if ([time length] == 23) {
        NSMutableString *str = [[[NSMutableString alloc] initWithFormat:@"%@000",time] autorelease];
        return str;
    }
    return time;
}

- (void)refreshTimerFired:(NSTimer *)timer
{
    [self startSynchronize:nil];
}

- (NSDictionary *)startNetworkGETRequestWithUrl:(NSURL *)url
{
    ASIHTTPRequest *request = [ASIHTTPRequest requestWithURL:url];
    __block NSDictionary *response;
    __block BOOL success = YES;
    
    [request setDelegate:self];
    
    [request setCompletionBlock:^{
        NSString *responseString = [request responseString];
        NSLog(@"\nSuccess response: %@", responseString);
        response = [responseString JSONValue];
    }];
    [request setFailedBlock:^{
        NSError *error = [request error];
        NSLog(@"\nError: %@", error.localizedDescription);
        NSString *responseString = [request responseString];
        NSLog(@"\nError Response: %@", responseString);
        success = NO;
    }];
    [request startSynchronous];
    
    if (success == NO) {
        return nil;
    }
    
    if (![(NSString *)[response valueForKey:@"status"] isEqualToString:@"success"]) {
        return nil;
    }
    
    return (NSDictionary *)[response valueForKey:@"response"];
}

- (NSDictionary *)startNetworkPOSTRequestWithUrl:(NSURL *)url postValues:(NSArray *)values forKeys:(NSArray *)keys
{
    ASIFormDataRequest *request = [ASIFormDataRequest requestWithURL:url];
    __block NSDictionary *response;
    int num = [values count];
    __block BOOL success = YES;
    
    for (int i = 0; i < num; i++) {
        [request setPostValue:[values objectAtIndex:i] forKey:[keys objectAtIndex:i]];
    }    
    [request setDelegate:self];
    
    [request setCompletionBlock:^{
        NSString *responseString = [request responseString];
        NSLog(@"\nSuccess response: %@", responseString);
        response = [responseString JSONValue];
    }];
    [request setFailedBlock:^{
        NSError *error = [request error];
        NSLog(@"\nError: %@", error.localizedDescription);
        NSString *responseString = [request responseString];
        NSLog(@"\nError Response: %@", responseString);
        success = NO;
    }];
    [request startSynchronous];
    
    if (success == NO) {
        return nil;
    }
    
    if (![(NSString *)[response valueForKey:@"status"] isEqualToString:@"success"]) {
        return nil;
    }
    
    return (NSDictionary *)[response valueForKey:@"response"];
}

-(void)saveUserInfo
{
    sqlite3_stmt *statement;
    const char *sql = "DELETE FROM userInfo;";
    if (sqlite3_prepare_v2(_database, sql, -1, &statement, NULL) != SQLITE_OK) {
        NSAssert1(0, @"Error: failed to prepare statement with message '%s'.", sqlite3_errmsg(_database));
    }
    
    [self setUpdateTime:DefaultSyncDate];
    if (sqlite3_step(statement) == SQLITE_DONE) {
        sqlite3_stmt *stmt = nil;
        const char *s = "INSERT INTO userInfo(svid,username,email,private_key,synctime) VALUES(?,?,?,?,?);";
        if (sqlite3_prepare_v2(_database, s, -1, &stmt, NULL) != SQLITE_OK) {
            NSAssert1(0, @"Error: failed to prepare statement with message '%s'.", sqlite3_errmsg(_database));
        }
        sqlite3_bind_text(stmt, 1, [_publicKey UTF8String], -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 2, [_author UTF8String], -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 3, [_email UTF8String], -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 4, [_privateKey UTF8String], -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 5, [_updateTime UTF8String], -1, SQLITE_TRANSIENT);
        if (sqlite3_step(stmt) != SQLITE_DONE) {
            NSAssert1(0, @"Error: failed to update new user info with message '%s'.", sqlite3_errmsg(_database));
        }
        sqlite3_finalize(stmt);
    } else {
        NSAssert1(0, @"Error: failed to delete old user info with message '%s'.", sqlite3_errmsg(_database));
    }
    
    sqlite3_finalize(statement);
}

- (void)logOutHandle:(NSNotification *)notification
{
    BOOL success = YES;
    sqlite3_stmt *stmt = nil;
    const char *s0 = "DELETE FROM userInfo;";
    const char *s1 = "DELETE FROM noteTable;";
    const char *s2 = "DELETE FROM tagTable;";
    const char *s3 = "DELETE FROM tagInNote;";
    if (sqlite3_prepare_v2(_database, s0, -1, &stmt, NULL) != SQLITE_OK) {
        NSAssert1(0, @"Error: failed to prepare statement with message '%s'.", sqlite3_errmsg(_database));
        success = NO;
    }
    if (sqlite3_step(stmt) != SQLITE_DONE) {
        NSAssert1(0, @"Error: failed to delete userinfo with message '%s'.", sqlite3_errmsg(_database));
        success = NO;
    }
    sqlite3_finalize(stmt);
    
    if (sqlite3_prepare_v2(_database, s1, -1, &stmt, NULL) != SQLITE_OK) {
        NSAssert1(0, @"Error: failed to prepare statement with message '%s'.", sqlite3_errmsg(_database));
        success = NO;
    }
    if (sqlite3_step(stmt) != SQLITE_DONE) {
        NSAssert1(0, @"Error: failed to delete noteTable with message '%s'.", sqlite3_errmsg(_database));
        success = NO;
    }
    sqlite3_finalize(stmt);
    
    if (sqlite3_prepare_v2(_database, s2, -1, &stmt, NULL) != SQLITE_OK) {
        NSAssert1(0, @"Error: failed to prepare statement with message '%s'.", sqlite3_errmsg(_database));
        success = NO;
    }
    if (sqlite3_step(stmt) != SQLITE_DONE) {
        NSAssert1(0, @"Error: failed to delete tagTable with message '%s'.", sqlite3_errmsg(_database));
        success = NO;
    }
    sqlite3_finalize(stmt);
    
    if (sqlite3_prepare_v2(_database, s3, -1, &stmt, NULL) != SQLITE_OK) {
        NSAssert1(0, @"Error: failed to prepare statement with message '%s'.", sqlite3_errmsg(_database));
        success = NO;
    }
    
    if (sqlite3_step(stmt) != SQLITE_DONE) {
        NSAssert1(0, @"Error: failed to delete tagInNote with message '%s'.", sqlite3_errmsg(_database));
        success = NO;
    }
    sqlite3_finalize(stmt);
    
    if (success) {
        [_notes removeAllObjects];
        [_tags removeAllObjects];
        [_selectedTags removeAllObjects];
        [_filteredNotes removeAllObjects];
        [_buttonsDictionary removeAllObjects];
        [_noteTableView reloadData];
        
        [self setPublicKey:@""];
        [self setPrivateKey:@""];
        [self setAuthor:@""];
        [self setEmail:@""];
        [self setUpdateTime:DefaultSyncDate];
    }
    
    [_settingsViewController logOutResultSentBack:success];
}

- (void)loginHandle:(NSNotification *)notification
{
    NSDictionary *extraInfo = [notification userInfo];
    NSString *name = [extraInfo objectForKey:@"name"];
    NSStream *pwd = [extraInfo objectForKey:@"password"];
    
    NSURL *url = [NSURL URLWithString:@"http://www.fetchnotes.com/keys"];
    NSArray *values = [NSArray arrayWithObjects:@"aaven", @"aavenj@fetchnotes.com", name, pwd, nil];
    NSArray *keys = [NSArray arrayWithObjects:@"name", @"email", @"username", @"password", nil];
    NSDictionary *response = [self startNetworkPOSTRequestWithUrl:url postValues:values forKeys:keys];
    
    if (response != nil) {
        [self setAuthor:(NSString *)[response valueForKey:@"author"]];
        [self setEmail:(NSString *)[response valueForKey:@"email"]];
        [self setPrivateKey:(NSString *)[response valueForKey:@"private_key"]];
        [self setPublicKey:(NSString *)[response valueForKey:@"_id"]];
        [self saveUserInfo];
        [_settingsViewController logInResultSentBack:YES username:(NSString *)name email:(NSString *)_email];
        [self.navigationController dismissModalViewControllerAnimated:YES];
    } else {
        NSLog(@"Login error");
        [_settingsViewController logInResultSentBack:NO username:(NSString *)name email:(NSString *)_email];
    }
}

-(NSString*)digest:(NSString*)input
{
    const char *cstr = [input cStringUsingEncoding:NSUTF8StringEncoding];
    NSData *data = [NSData dataWithBytes:cstr length:input.length];
    
    uint8_t digest[CC_SHA1_DIGEST_LENGTH];
    
    CC_SHA1(data.bytes, data.length, digest);
    
    NSMutableString* output = [NSMutableString stringWithCapacity:CC_SHA1_DIGEST_LENGTH * 2];
    
    for(int i = 0; i < CC_SHA1_DIGEST_LENGTH; i++)
        [output appendFormat:@"%02x", digest[i]];
    
    return output;
    
}

-(NSString *)generateSignature:(NSDictionary *)dict {
    NSArray *sortedKeys = [[dict allKeys] sortedArrayUsingSelector: @selector(caseInsensitiveCompare:)];
    NSString *valueStr = [[NSString alloc] initWithString:@""];
    for (NSString *key in sortedKeys) {
        valueStr = [NSString stringWithFormat:@"%@%@",valueStr,(NSString *)[dict valueForKey:key]];
    }
    NSString *clearText = [[NSString alloc] initWithFormat:@"%@%@",_privateKey,valueStr];
    NSString *cipher = [self digest:clearText];
    
    [clearText release];
    return cipher;
}

-(BOOL)syncDeletedNotesFromServerToLocal {
    // 4. delete note from server: svid in local but not on server
    // find all notes on server whose mtime is later than last Update Time, delete from local
    NSDictionary *dict = [NSDictionary dictionaryWithObjectsAndKeys:_updateTime,@"after",_publicKey,@"public_key",nil];
    NSString *hash = [self generateSignature:dict];
    NSURL *get_deleted_notes_url = [NSURL URLWithString:[NSString stringWithFormat:@"http://www.fetchnotes.com/authors/%@/deleted_notes?after=%@&public_key=%@&signature=%@",_author,_updateTime,_publicKey,hash]];
    NSLog(@"get_deleted_notes_url:%@",get_deleted_notes_url);
    
    NSDictionary *response = [self startNetworkGETRequestWithUrl:get_deleted_notes_url];
    if (response != nil) {
        // loop through all the deleted notes
        for (NSDictionary *entity in response) {
            NSString *svid = [entity valueForKey:@"_id"];
            [self deleteNoteWithSvid:svid];
        }
        return YES;
    }
    
    NSLog(@"ERROR: delete from server to local");
    return NO;
}

-(BOOL)syncDeletedNotesFromLocalToServer{
    // 3. delete note from local: use a deleted bit to indicate, then delete local
    // loop local for the bit, delete from server if exists, delete from local
    while (sqlite3_step(sync_deleted_local_stmt) == SQLITE_ROW) {
        int nid = sqlite3_column_int(sync_deleted_local_stmt,0);
        NSString *svid = [NSString stringWithUTF8String:(char *)sqlite3_column_text(sync_deleted_local_stmt, 1)];
        NSDictionary *dict = [NSDictionary dictionaryWithObjectsAndKeys:@"true",@"delete",_publicKey,@"public_key",nil];
        NSString *hash = [self generateSignature:dict];
        
        NSURL *delete_note_url = [NSURL URLWithString:[NSString stringWithFormat:@"http://www.fetchnotes.com/authors/%@/notes/%@",_author,svid]];
        NSLog(@"delete_note_url:%@",delete_note_url);
        
        NSArray *values = [NSArray arrayWithObjects:@"true",_publicKey,hash, nil];
        NSArray *keys = [NSArray arrayWithObjects:@"delete",@"public_key",@"signature", nil];
        
        NSDictionary *response = [self startNetworkPOSTRequestWithUrl:delete_note_url postValues:values forKeys:keys];
        
        if (response != nil) {
            // delete the note from local db
            [self deleteNoteWithID:nid];
        } else {
            NSLog(@"delete note error");
            return NO;
        }
    }
    sqlite3_reset(sync_deleted_local_stmt);
    return YES;
}

- (BOOL)syncNewAndModifiedNotesFromServerToLocal {
    // 2. new note from server: new svid on server
    // find all notes on server whose mtime is later than last Update Time, if svid not exists in local, add the note
    NSDictionary *dict = [NSDictionary dictionaryWithObjectsAndKeys:_updateTime,@"after",_publicKey,@"public_key",nil];
    NSString *hash = [self generateSignature:dict];
    NSURL *get_all_notes_url = [NSURL URLWithString:[NSString stringWithFormat:@"http://www.fetchnotes.com/authors/%@/notes?after=%@&public_key=%@&signature=%@",_author,_updateTime,_publicKey,hash]];
    NSLog(@"get_all_notes_url:%@",get_all_notes_url);
    
    NSDictionary *response = [self startNetworkGETRequestWithUrl:get_all_notes_url];
    
    if (response != nil) {
        
        for (NSDictionary *entity in response) {
            NSString *svid = [entity valueForKey:@"_id"];
            NSString *stext = [entity valueForKey:@"text"];
            NSString *stime = [entity valueForKey:@"timestamp"];
            
            sqlite3_bind_text(sync_svid_exist_local_stmt, 1, [svid UTF8String], -1, SQLITE_TRANSIENT);
            int count = 0;
            while (sqlite3_step(sync_svid_exist_local_stmt) == SQLITE_ROW) {
                count = count + 1;
            }
            
            if (count == 0) {
//                sqlite3_bind_text(sync_insert_note_stmt, 1, [stext UTF8String], -1, SQLITE_TRANSIENT);
//                sqlite3_bind_text(sync_insert_note_stmt, 2, [svid UTF8String], -1, SQLITE_TRANSIENT);
//                if (sqlite3_step(sync_insert_note_stmt) == SQLITE_DONE) {
//                    NSLog(@"success add a new note from server to local %@",svid);
//                } else {
//                    NSAssert1(0, @"Error: failed to add a new note from server to local with message '%s'.", sqlite3_errmsg(_database));
//                }
//                sqlite3_reset(sync_insert_note_stmt);
                
                Note *nt = [[Note alloc] initWithPrimaryKey:-1 content:stext];
                [self addNewNote:nt];
                [nt release];
                int pk = [nt localId];
                
                sqlite3_stmt *update_time_stmt = nil;
                NSString *sql = [NSString stringWithFormat: @"UPDATE noteTable SET mtime='%@', svid='%@' WHERE nid='%d';",stime,svid,pk];
                NSLog(@"stmt :%@",sql);
                if (sqlite3_prepare_v2(_database, [sql UTF8String], -1, &update_time_stmt, NULL) != SQLITE_OK) {
                    NSAssert1(0, @"Error: failed to prepare statement with message '%s'.", sqlite3_errmsg(_database));
                }
                
                if (sqlite3_step(update_time_stmt) != SQLITE_DONE) {
                    NSAssert1(0, @"Error: failed to update mtime with message '%s'.", sqlite3_errmsg(_database));
                }
                
            } else if (count > 1) { 
                NSLog(@"Error: %d notes share the same svid",count);
            } else {
                // TODO try with prepared stmt
                sqlite3_stmt *stmt2 = nil;
                NSString *sql2 = [NSString stringWithFormat: @"UPDATE noteTable SET text=text||' CONFLICT %@ \n(the note on website is kept)', deleted=2 WHERE svid='%@' AND mtime>'%@';",stext,svid,_updateTime];
                NSLog(@"sql2 %@",sql2);
                if (sqlite3_prepare_v2(_database, [sql2 UTF8String], -1, &stmt2, NULL) != SQLITE_OK) {
                    NSAssert1(0, @"Error: failed to prepare statement with message '%s'.", sqlite3_errmsg(_database));
                }
                
                if (sqlite3_step(stmt2) != SQLITE_DONE) {
                    NSAssert1(0, @"Error: failed to mark conflict with message '%s'.", sqlite3_errmsg(_database));
                }
                
                // update the local note if localtime<=LUT
                sqlite3_stmt *stmt = nil;
                NSString *sql = [NSString stringWithFormat: @"UPDATE noteTable SET text='%@', deleted=2 WHERE svid='%@' AND mtime<='%@' AND deleted=0;",stext,svid,_updateTime];
                NSLog(@"stmt :%@",sql);
                if (sqlite3_prepare_v2(_database, [sql UTF8String], -1, &stmt, NULL) != SQLITE_OK) {
                    NSAssert1(0, @"Error: failed to prepare statement with message '%s'.", sqlite3_errmsg(_database));
                }
                
                if (sqlite3_step(stmt) == SQLITE_DONE) {                    
                    sqlite3_stmt *update_time_stmt = nil;
                    NSString *sql = [NSString stringWithFormat: @"UPDATE noteTable SET mtime='%@' WHERE svid='%@';",stime,svid];
                    NSLog(@"stmt :%@",sql);
                    if (sqlite3_prepare_v2(_database, [sql UTF8String], -1, &update_time_stmt, NULL) != SQLITE_OK) {
                        NSAssert1(0, @"Error: failed to prepare statement with message '%s'.", sqlite3_errmsg(_database));
                    }
                    
                    if (sqlite3_step(update_time_stmt) != SQLITE_DONE) {
                        NSAssert1(0, @"Error: failed to update mtime with message '%s'.", sqlite3_errmsg(_database));
                    }
                    
                } else {
                    NSAssert1(0, @"Error: failed to update from server to local with message '%s'.", sqlite3_errmsg(_database));
                }
                
                // update text and insert tags
                NSString *sss = [NSString stringWithFormat:@"SELECT nid,text FROM noteTable WHERE svid='%@' AND deleted!=1 AND mtime>'%@';",svid,_updateTime];
                NSLog(@"sss: %@",sss);
                sqlite3_stmt *ttt = nil;
                
                if (sqlite3_prepare_v2(_database, [sss UTF8String], -1, &ttt, NULL) == SQLITE_OK) {
                    while (sqlite3_step(ttt) == SQLITE_ROW) {
                        int pk = sqlite3_column_int(ttt, 0);
                        for (Note *nt in _notes) {
                            if ([nt localId] == pk) {
                                NSMutableArray *oldtags = [[nt containedTags] mutableCopy];
                                [nt updateText:[NSString stringWithUTF8String:(char *)sqlite3_column_text(ttt, 1)]];
                                NSMutableArray *newtags = [nt containedTags];
                                
                                for (NSString *tag in oldtags) {
                                    [self deleteOldPairAndTag:tag withNoteID:pk];
                                }
                                [oldtags release];
                                
                                for (NSString *tag in newtags) {
                                    [self saveNewTagAndPair:tag noteID:pk];
                                }
                                break;
                            }
                        }
                    }
                }
                sqlite3_finalize(ttt);

            }
            sqlite3_reset(sync_svid_exist_local_stmt);
            
        }
        return YES;
    }
    return NO;
}

- (BOOL)syncNewNoteAndModifiedNotesFromLocalToServer {
    // for modified updatable local notes whose mtime>LUT, update to server
    //sqlite3_bind_text(sync_load_modified_notes_stmt, 1, [_updateTime UTF8String], -1, SQLITE_TRANSIENT);
    sqlite3_stmt *stmt = nil;
    NSString *sql = [NSString stringWithFormat: @"SELECT * FROM noteTable WHERE mtime>'%@' AND svid IS NOT NULL AND svid!='' AND deleted=0;",_updateTime];
    NSLog(@"localtoserver :%@",sql);
    if (sqlite3_prepare_v2(_database, [sql UTF8String], -1, &stmt, NULL) != SQLITE_OK) {
        NSAssert1(0, @"Error: failed to prepare statement with message '%s'.", sqlite3_errmsg(_database));
    }

    while (sqlite3_step(stmt) == SQLITE_ROW) {
        NSString *svid = [NSString stringWithUTF8String:(char *)sqlite3_column_text(stmt, 3)];
        NSString *text = [NSString stringWithUTF8String:(char *)sqlite3_column_text(stmt, 1)];
        NSDictionary *dict = [NSDictionary dictionaryWithObjectsAndKeys:text,@"text",_publicKey,@"public_key",nil];
        NSString *hash = [self generateSignature:dict];
        
        NSURL *modify_note_url = [NSURL URLWithString:[NSString stringWithFormat:@"http://www.fetchnotes.com/authors/%@/notes/%@",_author,svid]];
        NSLog(@"modify_note_url:%@",modify_note_url);
        
        NSArray *values = [NSArray arrayWithObjects:text,_publicKey,hash, nil];
        NSArray *keys = [NSArray arrayWithObjects:@"text",@"public_key",@"signature", nil];
        
        NSDictionary *response = [self startNetworkPOSTRequestWithUrl:modify_note_url postValues:values forKeys:keys];
        
        if (!response) {
            NSLog(@"upload modified note error");
            return NO;
        }
    }
//    sqlite3_reset(sync_load_modified_notes_stmt);
    sqlite3_finalize(stmt);
    
    // add new note to server
    while (sqlite3_step(sync_empty_svid_local_stmt) == SQLITE_ROW) {
        int nid = sqlite3_column_int(sync_empty_svid_local_stmt,0);
        NSString *text = [NSString stringWithUTF8String:(char *)sqlite3_column_text(sync_empty_svid_local_stmt, 1)];
        NSDictionary *dict = [NSDictionary dictionaryWithObjectsAndKeys:_publicKey,@"public_key",text,@"text",nil];
        NSString *hash = [self generateSignature:dict];
        
        NSURL *add_new_note_url = [NSURL URLWithString:[NSString stringWithFormat:@"http://www.fetchnotes.com/authors/%@/notes",_author]];
        NSLog(@"add_new_note_url:%@",add_new_note_url);
        
        NSArray *values = [NSArray arrayWithObjects:text,_publicKey,hash, nil];
        NSArray *keys = [NSArray arrayWithObjects:@"text",@"public_key",@"signature", nil];
        NSDictionary *response = [self startNetworkPOSTRequestWithUrl:add_new_note_url postValues:values forKeys:keys];
        
        if (response != nil) {
            NSString *svid = (NSString *)[response valueForKey:@"_id"];
            NSString *mtime = (NSString *)[response valueForKey:@"timestamp"];
            NSLog(@"svid:%@,mtime:%@",svid,mtime);
            // update svid and mtime in local db
            sqlite3_bind_text(sync_update_svid_mtime_local_stmt, 1, [svid UTF8String], -1, SQLITE_TRANSIENT);
            sqlite3_bind_int(sync_update_svid_mtime_local_stmt, 2, nid);
            if (sqlite3_step(sync_update_svid_mtime_local_stmt) != SQLITE_DONE) {
                NSAssert1(0, @"Error: failed to save local notetext and time with message '%s'.", sqlite3_errmsg(_database));
                return NO;
            }
            sqlite3_reset(sync_update_svid_mtime_local_stmt);
        }
    }
    sqlite3_reset(sync_empty_svid_local_stmt);
    return YES;
}

- (void)startSynchronize:(NSNotification *)notif {
    BOOL success = YES;
    if (_author == nil) {
        [self DisplayAlert:@"Welcome to fetchnotes!" andMessage:@"Please log in before you sync or sign up on www.fetchnotes.com!"];
        return;
    }
    if ([_author isEqual:@""]) {
        [self DisplayAlert:@"Welcome to fetchnotes!" andMessage:@"Please log in before you sync or sign up on www.fetchnotes.com!"];
        return;
    }
    
    [_loadingIndicator startAnimating];
    [self.view bringSubviewToFront:_loadingIndicator];
    
    if (sqlite3_step(sync_load_synctime_stmt) == SQLITE_ROW) {
        [self setUpdateTime:[self formatDatetimeToServer:[NSString stringWithUTF8String:(char *)sqlite3_column_text(sync_load_synctime_stmt, 0)]]];
    } 
    sqlite3_reset(sync_load_synctime_stmt);
    
    NSLog(@"start synchronize, last updateTime short:%@",_updateTime);
    
    success = [self syncDeletedNotesFromServerToLocal]
    && [self syncDeletedNotesFromLocalToServer]
    && [self syncNewAndModifiedNotesFromServerToLocal]
    && [self syncNewNoteAndModifiedNotesFromLocalToServer];
    
    
    if (success) {
        // update deleted bit to 0
        if (sqlite3_step(sync_reset_delete_bit_stmt) != SQLITE_DONE) {
            NSLog(@"fail to reset delete bit");
        }
        sqlite3_reset(sync_reset_delete_bit_stmt);
        
        [self loadAllNotes];
        [self loadAllTags];
        [_noteTableView reloadData];
        [self arrangeButtons];
        if (_filterIsUp) {
            [self filterViewUp];
        }
        
        // update last-update-time to local db
        if (sqlite3_step(sync_change_update_time_local_stmt) != SQLITE_DONE) {
            NSAssert1(0, @"Error: failed to change synctime with message '%s'.", sqlite3_errmsg(_database));
        } 
        sqlite3_reset(sync_change_update_time_local_stmt);
    } else {
        NSLog(@"fail syncing");
    }
    
    [_loadingIndicator stopAnimating];
}

- (void)refreshButtonClicked:(id)sender {
    if (!_settingsViewController.loggedIn) {
        UIAlertView* alert = [[UIAlertView alloc] initWithTitle:@"Sorry" message:@"You must log in first to sync your notes." delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
        [alert show];
        [alert release];
        return;
    }
    
    [self startSynchronize:nil];
}

#pragma mark tag filtering system

- (void)tagClicked:(id)sender {
    UIButton *button = (UIButton *)sender;
    if (button.selected == NO) {
        [button setBackgroundImage:greyImage forState:UIControlStateNormal];
        button.selected = YES;
        [_selectedTags addObject:button.titleLabel.text];
    } else {
        [button setBackgroundImage:whiteImage forState:UIControlStateNormal]; 
        button.selected = NO;
        [_selectedTags removeObject:button.titleLabel.text];
    }   
    
    if (_selectedTags.count > 0) {
        [self filterTags];
    } else {
        _isFiltering = NO;
    }

    [self showSettingsOrAllNotesButton];
    [_noteTableView reloadData];
    [self arrangeButtons];
}

- (UIButton *)createTagButtonWithTag:(NSString *)tag
{
    UIButton *button = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    [button setTitle:tag forState:UIControlStateNormal];
    [button addTarget:self action:@selector(tagClicked:) forControlEvents:UIControlEventTouchUpInside];
    [button sizeToFit];
    [[button layer] setCornerRadius:10];
    [[button layer] setMasksToBounds:YES];
    [[button layer] setBorderWidth:1.0];
    [[button layer] setBorderColor:[[UIColor grayColor] CGColor]];
    if ([[tag substringToIndex:1] isEqualToString:@"@"]) {
        [button setTitleColor:[UIColor colorWithRed:0/255.0 green:255/255.0 blue:100/255.0 alpha:1.0] forState:UIControlStateNormal];
    } else {
        [button setTitleColor:[UIColor colorWithRed:0/255.0 green:167/255.0 blue:255/255.0 alpha:1.0] forState:UIControlStateNormal];
    }
    [button setBackgroundImage:whiteImage forState:UIControlStateNormal];
    button.selected = NO;
    
    return button;
}

- (void) filterViewDown {
    CGRect frame1 = _tagsFilterView.frame;
    CGRect frame2 = CGRectMake(0, 0, 320, HEIGHT_TABLE_FULL);
    frame1.origin.y = HEIGHT_TABLE_FULL;
    
    [UIView animateWithDuration:0.4
                          delay:0.0
                        options: UIViewAnimationCurveEaseOut
                     animations:^{
                         _tagsFilterView.frame = frame1;
                         _noteTableView.frame = frame2;
                     } 
                     completion:^(BOOL finished){}
     ];
    
    _filterIsUp = NO;
}

- (void) filterViewUp {
    CGRect frame1 = _tagsFilterView.frame;
    CGRect frame2 = CGRectMake(0, 0, 320, _yFilterUp);
    frame1.origin.y = _yFilterUp;
    
    [UIView animateWithDuration:0.4
                          delay:0.0
                        options: UIViewAnimationCurveEaseOut
                     animations:^{
                         _tagsFilterView.frame = frame1;
                     } 
                     completion:^(BOOL finished){
                         _noteTableView.frame = frame2;
                     }
     ];
    
    _filterIsUp = YES;
}

- (IBAction)tagButtonClicked:(id)sender
{
    if (_filterIsUp) {
        [self filterViewDown];
        [_filterViewControlButton setTintColor:[UIColor colorWithRed:0/255.0 green:167/255.0 blue:255.0/255.0 alpha:1.0]];
    } else {
        if ([_mySearchBar isFirstResponder]) {
            [self searchBarCancelButtonClicked:_mySearchBar];
        }
        
        [self filterViewUp];
        [_filterViewControlButton setTintColor:[UIColor colorWithRed:20.0/255.0 green:94.0/255.0 blue:255/255.0 alpha:1.0]];
        
    }
}

- (void)arrangeButtons
{
    int row = 0;
    int offset = 3;
    double height = 0;
    CGRect frame;
    UIButton *button;
    
    for (UIView *view in [_tagsFilterView subviews]) {
        [view removeFromSuperview];
    }
    NSArray *allTags = [[_buttonsDictionary allKeys] sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];
    
    
    if (allTags.count == 0) {
        // show a message in the filterview
        frame = _tagsFilterView.frame;
        frame.size.height = HEIGHT_MESSAGE;
        
        UILabel *newLabel = [[UILabel alloc] initWithFrame:CGRectMake(5, 2, 310, 44)];
        newLabel.backgroundColor = [UIColor whiteColor];
        newLabel.opaque = YES;
        newLabel.textColor = [UIColor blackColor];
        newLabel.highlightedTextColor = [UIColor whiteColor];
        newLabel.font = [UIFont fontWithName:@"Arial" size:16.0];
        newLabel.lineBreakMode = UILineBreakModeWordWrap;
        newLabel.numberOfLines = 0;
        newLabel.text = @"There is no tag yet. Create a tag by adding # or @ in your note.";
        [_tagsFilterView addSubview:newLabel];
        [newLabel release];
    } else {
        for (NSString *tag in allTags) {
            button = [_buttonsDictionary objectForKey:tag];
            frame = button.frame;
            if (offset + frame.size.width >= 320) {
                row = row + 1;
                offset = MARGIN_X_FILTERVIEW;
            }
            if (frame.size.width > 156) {
                frame.size.width = 156;
            } else {
                frame.size.width = frame.size.width;
            }
            frame.origin.x = offset;
            frame.origin.y = row * (HEIGHT_TAG + MARGIN_Y_FILTERVIEW) + MARGIN_Y_FILTERVIEW;
            button.frame = frame;
            [_tagsFilterView addSubview:button];
            
            offset = offset + frame.size.width + MARGIN_X_FILTERVIEW;
        }
        
        height = (row + 1) * (HEIGHT_TAG + MARGIN_Y_FILTERVIEW) + MARGIN_Y_FILTERVIEW;
        _tagsFilterView.contentSize = CGSizeMake(320, height);
        frame = _tagsFilterView.frame;
        if (height > MAX_HEIGHT_FILTERVIEW) {
            frame.size.height = MAX_HEIGHT_FILTERVIEW;
        } else {
            frame.size.height = height;
        }
    }
    
    _yFilterUp = HEIGHT_TABLE_FULL - frame.size.height;
    _tagsFilterView.frame = frame;
    
    if (_filterIsUp) {
        _tagsFilterView.frame = frame;
        _noteTableView.frame = CGRectMake(0, 0, 320, _yFilterUp);;
    }
}

#pragma mark database methods

- (void)deleteNoteWithSvid:(NSString *)svid {
    
    
    NSString *sql = [NSString stringWithFormat:@"SELECT nid FROM noteTable WHERE svid='%@' AND deleted=0;",svid];
    NSLog(@"sql svid: %@",sql);
    sqlite3_stmt *stmt = nil;
    
    if (sqlite3_prepare_v2(_database, [sql UTF8String], -1, &stmt, NULL) == SQLITE_OK) {
        if (sqlite3_step(stmt) == SQLITE_ROW) {
            int pk = sqlite3_column_int(stmt, 0);
            
            NSString *sql2 = [NSString stringWithFormat:@"SELECT DISTINCT tag FROM tagInNote WHERE nid=%d;",pk];
            NSLog(@"sql pk: %@",sql2);
            sqlite3_stmt *stmt2 = nil;
            
            if (sqlite3_prepare_v2(_database, [sql2 UTF8String], -1, &stmt2, NULL) == SQLITE_OK) {
                while (sqlite3_step(stmt2) == SQLITE_ROW) {
                    NSLog(@"tag: %@",[NSString stringWithUTF8String:(char *)sqlite3_column_text(stmt2, 0)]);
                    [self deleteOldPairAndTag:[NSString stringWithUTF8String:(char *)sqlite3_column_text(stmt2, 0)] withNoteID:pk];
                }
            }
            sqlite3_finalize(stmt2);

        }
    }
    sqlite3_finalize(stmt);
    
	
    sqlite3_bind_text(sync_delete_note_stmt, 1, [svid UTF8String], -1, SQLITE_TRANSIENT);
    if (sqlite3_step(sync_delete_note_stmt) != SQLITE_DONE) {
        NSLog(@"error delete a note from local with svid %@",svid);
    }
    sqlite3_reset(sync_delete_note_stmt);
}

- (void)deleteNoteWithID:(int)pk {
    
	sqlite3_bind_int(delete_note_statement, 1, pk);
	if (sqlite3_step(delete_note_statement) != SQLITE_DONE) {
		NSAssert1(0, @"Error: failed to delete note with message '%s'.", sqlite3_errmsg(_database));
	}
	
	sqlite3_reset(delete_note_statement);
}

- (void)filterTags{
    [_filteredNotes removeAllObjects];
    NSString *sql = [NSString stringWithFormat:@"SELECT nid FROM noteTable WHERE nid IN (SELECT nid FROM tagInNote WHERE 0"];
//    NSString *sql2 = [NSString stringWithFormat:@"SELECT DISTINCT tag FROM tagInNote WHERE 0"];
    for (NSString *tag in _selectedTags) {
        sql = [NSString stringWithFormat:@"%@ OR tag='%@'", sql, tag];
    }
    sql = [NSString stringWithFormat:@"%@ GROUP BY nid HAVING COUNT(*)=%d) ORDER BY mtime DESC;", sql, [_selectedTags count]];
    NSLog(@"sql: %@",sql);
    sqlite3_stmt *stmt = nil;
    
    if (sqlite3_prepare_v2(_database, [sql UTF8String], -1, &stmt, NULL) == SQLITE_OK) {
        while (sqlite3_step(stmt) == SQLITE_ROW) {
            int pk = sqlite3_column_int(stmt, 0);
            for (Note *note in _notes) {
                if ([note localId] == pk) {
                    [_filteredNotes addObject:note];
                    break;
                }
            }
        }
    }
    sqlite3_finalize(stmt);
    
    _isFiltering = YES;
}

- (BOOL)checkIfUserExists
{
    if (sqlite3_step(sync_load_user_info_stmt) == SQLITE_ROW) {
        [self setPublicKey:[NSString stringWithUTF8String:(char *)sqlite3_column_text(sync_load_user_info_stmt, 0)]];
        [self setAuthor:[NSString stringWithUTF8String:(char *)sqlite3_column_text(sync_load_user_info_stmt, 1)]];
        [self setEmail:[NSString stringWithUTF8String:(char *)sqlite3_column_text(sync_load_user_info_stmt, 2)]];
        [self setPrivateKey:[NSString stringWithUTF8String:(char *)sqlite3_column_text(sync_load_user_info_stmt, 4)]];
        [self setUpdateTime:[self formatDatetimeToServer:[NSString stringWithUTF8String:(char *)sqlite3_column_text(sync_load_user_info_stmt, 5)]]];
        sqlite3_reset(sync_load_user_info_stmt);
        
        return YES;
    } else {
        NSLog(@"no existing user info");
        sqlite3_reset(sync_load_user_info_stmt);
        return NO;
    }
}

-(void)initializeStatements {
    
    if (sync_reset_delete_bit_stmt == nil) {
        const char *sql = "UPDATE noteTable SET deleted=0 WHERE deleted=2;";
        if (sqlite3_prepare_v2(_database, sql, -1, &sync_reset_delete_bit_stmt, NULL) != SQLITE_OK) {
            NSAssert1(0, @"Error: failed to prepare statement with message '%s'.", sqlite3_errmsg(_database));
        }
    }
    
    if (mark_delete_note_stmt == nil) {
        const char *sql = "UPDATE noteTable SET deleted=1 WHERE nid=?;";
        if (sqlite3_prepare_v2(_database, sql, -1, &mark_delete_note_stmt, NULL) != SQLITE_OK) {
            NSAssert1(0, @"Error: failed to prepare statement with message '%s'.", sqlite3_errmsg(_database));
        }
    }
    
    if (sync_load_synctime_stmt == nil) {
        const char *sql = "SELECT synctime FROM userInfo WHERE synctime IS NOT NULL;";
        if (sqlite3_prepare_v2(_database, sql, -1, &sync_load_synctime_stmt, NULL) != SQLITE_OK) {
            NSAssert1(0, @"Error: failed to prepare statement with message '%s'.", sqlite3_errmsg(_database));
        }
    }
    
    if (sync_load_user_info_stmt == nil) {
        const char *sql = "SELECT * FROM userInfo;";
        if (sqlite3_prepare_v2(_database, sql, -1, &sync_load_user_info_stmt, NULL) != SQLITE_OK) {
            NSAssert1(0, @"Error: failed to prepare statement with message '%s'.", sqlite3_errmsg(_database));
        }
    }
    
    if (sync_load_modified_notes_stmt == nil) { // TODO
        const char *sql = "SELECT * FROM noteTable WHERE mtime>'?' AND svid IS NOT NULL AND svid!='' AND deleted=0;";
        if (sqlite3_prepare_v2(_database, sql, -1, &sync_load_modified_notes_stmt, NULL) != SQLITE_OK) {
            NSAssert1(0, @"Error: failed to prepare statement with message '%s'.", sqlite3_errmsg(_database));
        }
    }
    
    if (sync_delete_note_stmt == nil) {
        const char *sql = "DELETE FROM noteTable WHERE svid=?;";
        if (sqlite3_prepare_v2(_database, sql, -1, &sync_delete_note_stmt, NULL) != SQLITE_OK) {
            NSAssert1(0, @"Error: failed to prepare statement with message '%s'.", sqlite3_errmsg(_database));
        }
    }
    
    if (sync_change_update_time_local_stmt == nil) {
        const char *sql = "UPDATE userInfo SET synctime=(SELECT MAX(mtime) FROM noteTable);";
        if (sqlite3_prepare_v2(_database, sql, -1, &sync_change_update_time_local_stmt, NULL) != SQLITE_OK) {
            NSAssert1(0, @"Error: failed to prepare statement with message '%s'.", sqlite3_errmsg(_database));
        }
    }
    
    if (sync_deleted_local_stmt == nil) {
        const char *sql = "SELECT nid,svid FROM noteTable WHERE deleted=1 AND svid IS NOT NULL AND svid!='';";
        if (sqlite3_prepare_v2(_database, sql, -1, &sync_deleted_local_stmt, NULL) != SQLITE_OK) {
            NSAssert1(0, @"Error: failed to prepare statement with message '%s'.", sqlite3_errmsg(_database));
        }
    }
    
    if (sync_svid_exist_local_stmt == nil) {
        const char *sql = "SELECT nid FROM noteTable WHERE svid=?;";
        if (sqlite3_prepare_v2(_database, sql, -1, &sync_svid_exist_local_stmt, NULL) != SQLITE_OK) {
            NSAssert1(0, @"Error: failed to prepare statement with message '%s'.", sqlite3_errmsg(_database));
        }
    }
    
    if (sync_update_svid_mtime_local_stmt == nil) {
        const char *sql = "UPDATE noteTable SET svid=? WHERE nid=?;";
        if (sqlite3_prepare_v2(_database, sql, -1, &sync_update_svid_mtime_local_stmt, NULL) != SQLITE_OK) {
            NSAssert1(0, @"Error: failed to prepare statement with message '%s'.", sqlite3_errmsg(_database));
        }
    }
    
    if (sync_empty_svid_local_stmt == nil) {
        const char *sql = "SELECT * FROM noteTable WHERE (svid is NULL or svid='') AND deleted=0;";
        if (sqlite3_prepare_v2(_database, sql, -1, &sync_empty_svid_local_stmt, NULL) != SQLITE_OK) {
            NSAssert1(0, @"Error: failed to prepare statement with message '%s'.", sqlite3_errmsg(_database));
        }
    }
    
    if (load_notes_stmt == nil) {
        const char *sql = "SELECT nid,text FROM noteTable WHERE deleted!=1 ORDER BY mtime DESC;";
        if (sqlite3_prepare_v2(_database, sql, -1, &load_notes_stmt, NULL) != SQLITE_OK) {
            NSAssert1(0, @"Error: failed to prepare statement with message '%s'.", sqlite3_errmsg(_database));
        }
    }
    
    if (load_tags_stmt == nil) {
        const char *sql = "SELECT DISTINCT tag FROM tagInNote;";
        if (sqlite3_prepare_v2(_database, sql, -1, &load_tags_stmt, NULL) != SQLITE_OK) {
            NSAssert1(0, @"Error: failed to prepare statement with message '%s'.", sqlite3_errmsg(_database));
        }
    }
    
    if (update_note_text_statment == nil) {
        const char *sql = "UPDATE noteTable SET text = ? WHERE nid=?";
        if (sqlite3_prepare_v2(_database, sql, -1, &update_note_text_statment, NULL) != SQLITE_OK) {
            NSAssert1(0, @"Error: failed to prepare statement with message '%s'.", sqlite3_errmsg(_database));
        }
    }
    
    if (count_paired_tag_statement == nil) {
        const char *sql = "SELECT * FROM tagInNote WHERE tag=?;";
        if (sqlite3_prepare_v2(_database, sql, -1, &count_paired_tag_statement, NULL) != SQLITE_OK) {
            NSAssert1(0, @"Error: failed to prepare statement with message '%s'.", sqlite3_errmsg(_database));
        }
    }
    
    if (delete_tag_statement == nil) {
        const char *sql = "DELETE FROM tagTable WHERE text=?";
        if (sqlite3_prepare_v2(_database, sql, -1, &delete_tag_statement, NULL) != SQLITE_OK) {
            NSAssert1(0, @"Error: failed to prepare statement with message '%s'.", sqlite3_errmsg(_database));
        }
    }
    
    if (delete_pair_statement == nil) {
        const char *sql = "DELETE FROM tagInNote WHERE tag=? AND nid=?";
        if (sqlite3_prepare_v2(_database, sql, -1, &delete_pair_statement, NULL) != SQLITE_OK) {
            NSAssert1(0, @"Error: failed to prepare statement with message '%s'.", sqlite3_errmsg(_database));
        }
    }
    
    if (insert_tag_statement == nil) {
        const char *sql = "INSERT OR IGNORE INTO tagTable(text) VALUES(?);";
        if (sqlite3_prepare_v2(_database, sql, -1, &insert_tag_statement, NULL) != SQLITE_OK) {
            NSAssert1(0, @"Error: failed to prepare statement with message '%s'.", sqlite3_errmsg(_database));
        }
    }
    
    if (insert_pair_statement == nil) {
        const char *sql = "INSERT OR IGNORE INTO tagInNote(tag,nid) VALUES(?,?);";
        if (sqlite3_prepare_v2(_database, sql, -1, &insert_pair_statement, NULL) != SQLITE_OK) {
            NSAssert1(0, @"Error: failed to prepare statement with message '%s'.", sqlite3_errmsg(_database));
        }
    }
    
    if (delete_note_statement == nil) {
        const char *sql = "DELETE FROM noteTable WHERE nid=?";
        if (sqlite3_prepare_v2(_database, sql, -1, &delete_note_statement, NULL) != SQLITE_OK) {
            NSAssert1(0, @"Error: failed to prepare statement with message '%s'.", sqlite3_errmsg(_database));
        }
    }
    
    if (insert_note_statement == nil) {
        static char *sql = "INSERT INTO noteTable (text) VALUES(?);";
        if (sqlite3_prepare_v2(_database, sql, -1, &insert_note_statement, NULL) != SQLITE_OK) {
            NSAssert1(0, @"Error: failed to prepare statement with message '%s'.", sqlite3_errmsg(_database));
        }
    }
}

-(void)loadAllNotes {
    [_notes removeAllObjects];
    while (sqlite3_step(load_notes_stmt) == SQLITE_ROW) {
        int primaryKey = sqlite3_column_int(load_notes_stmt, 0);
        NSString *text = [NSString stringWithUTF8String:(char *)sqlite3_column_text(load_notes_stmt, 1)];
        Note *note = [[Note alloc] initWithPrimaryKey:primaryKey content:text];
        [_notes addObject:note];
        [note release];
    }
    sqlite3_reset(load_notes_stmt);
}

-(void)loadAllTags {
    while (sqlite3_step(load_tags_stmt) == SQLITE_ROW) {
        NSString *tag = [NSString stringWithUTF8String:(char *)sqlite3_column_text(load_tags_stmt, 0)];
        [_tags addObject:tag];
        [_buttonsDictionary setValue:[self createTagButtonWithTag:tag] forKey:tag];
    }
    sqlite3_reset(load_tags_stmt);
}

-(void)deleteTag:(NSString *)tag {
    sqlite3_bind_text(delete_tag_statement, 1, [tag UTF8String], -1, SQLITE_TRANSIENT);
    if (sqlite3_step(delete_tag_statement) != SQLITE_DONE) {
        NSAssert1(0, @"Error: failed to delete tag with message '%s'.", sqlite3_errmsg(_database));
    }
    sqlite3_reset(delete_tag_statement);
}

-(void)deleteOldPairAndTag:(NSString *)oldtag withNoteID:(int)pk {
    sqlite3_bind_int(delete_pair_statement, 2, pk);
    sqlite3_bind_text(delete_pair_statement, 1, [oldtag UTF8String], -1, SQLITE_TRANSIENT);
    if (sqlite3_step(delete_pair_statement) != SQLITE_DONE) {
        NSAssert1(0, @"Error: failed to delete pair with message '%s'.", sqlite3_errmsg(_database));
    }
    sqlite3_reset(delete_pair_statement);
    
    sqlite3_bind_text(count_paired_tag_statement, 1, [oldtag UTF8String], -1, SQLITE_TRANSIENT);
    if (sqlite3_step(count_paired_tag_statement) == SQLITE_ROW) {
        NSLog(@"DBC: %@ still exists in other notes, not deleted.", oldtag);
    } else {
        NSLog(@"DBC: %@ is deleted with deleted note #%d.", oldtag, pk);
        [self deleteTag:oldtag];
        [_buttonsDictionary removeObjectForKey:oldtag];
        [self arrangeButtons];
    }
    sqlite3_reset(count_paired_tag_statement);
    
}

-(void)markDeletedNoteWithID:(int)pk {
	sqlite3_bind_int(mark_delete_note_stmt, 1, pk);
	if (sqlite3_step(mark_delete_note_stmt) != SQLITE_DONE) {
		NSAssert1(0, @"Error: failed to delete note with message '%s'.", sqlite3_errmsg(_database));
	}
	sqlite3_reset(mark_delete_note_stmt);
}

-(void)completelyDeleteNoteWithID:(int)pk {
	sqlite3_bind_int(delete_note_statement, 1, pk);
	if (sqlite3_step(delete_note_statement) != SQLITE_DONE) {
		NSAssert1(0, @"Error: failed to delete note with message '%s'.", sqlite3_errmsg(_database));
	}
	sqlite3_reset(delete_note_statement);
}

-(void) deleteFromDatabase:(Note *)note completely:(BOOL)sure {
    if (sure) {
        [self completelyDeleteNoteWithID:note.localId];
    } else {
        [self markDeletedNoteWithID:note.localId];
    }
    NSMutableArray *oldtags = [note containedTags];
    int pk = [note localId];
    for (NSMutableString *tag in oldtags) {
        [self deleteOldPairAndTag:tag withNoteID:pk];
    }
}

-(void)saveNewTagAndPair:(NSString *)tag noteID:(int)pk {
    sqlite3_bind_text(insert_tag_statement, 1, [tag UTF8String], -1, SQLITE_TRANSIENT);
    if (sqlite3_step(insert_tag_statement) != SQLITE_DONE) {
        NSAssert1(0, @"Error: failed to save tag with message '%s'.", sqlite3_errmsg(_database));
    }
    sqlite3_reset(insert_tag_statement);
    if ([_buttonsDictionary objectForKey:tag] == nil) {
        [_buttonsDictionary setValue:[self createTagButtonWithTag:tag] forKey:tag];
    }
    
    sqlite3_bind_int(insert_pair_statement, 2, pk);
    sqlite3_bind_text(insert_pair_statement, 1, [tag UTF8String], -1, SQLITE_TRANSIENT);
    if (sqlite3_step(insert_pair_statement) != SQLITE_DONE) {
        NSAssert1(0, @"Error: failed to save pair tag with message '%s'.", sqlite3_errmsg(_database));
    }
    sqlite3_reset(insert_pair_statement);
}

-(void)addNewNote:(Note *)note {
    sqlite3_bind_text(insert_note_statement, 1, [note.noteText UTF8String], -1, SQLITE_TRANSIENT);
    if (sqlite3_step(insert_note_statement) != SQLITE_ERROR) {
        [note setLocalId:sqlite3_last_insert_rowid(_database)];
    } else {
        NSAssert1(0, @"Error: failed to insert into the database with message '%s'.", sqlite3_errmsg(_database));
        [note setLocalId:-1];
    }
    sqlite3_reset(insert_note_statement);
    
    NSMutableArray *newtags = [note containedTags];
    int pk = [note localId];
    for (NSString *tag in newtags) {
        [self saveNewTagAndPair:tag noteID:pk];
    }
}

-(void)updateNoteText:(Note *)note {
    sqlite3_bind_int(update_note_text_statment, 2, [note localId]);
    sqlite3_bind_text(update_note_text_statment, 1, [[note noteText] UTF8String], -1, SQLITE_TRANSIENT);
    if (sqlite3_step(update_note_text_statment) != SQLITE_DONE) {
        NSAssert1(0, @"Error: failed to save note text with message '%s'.", sqlite3_errmsg(_database));
    }
    sqlite3_reset(update_note_text_statment);
}

- (void)redirectWithOneTag:(NSNotification *)notification
{
    NSDictionary *extraInfo = [notification userInfo];
    NSString *newtag = [extraInfo objectForKey:@"tag"];
    UIButton *button;
    for (NSString *tag in _selectedTags) {
        button = [_buttonsDictionary objectForKey:tag];
        [button setBackgroundImage:whiteImage forState:UIControlStateNormal]; 
        button.selected = NO;
    }
    [_selectedTags removeAllObjects];
    [_selectedTags addObject:newtag];
    button = [_buttonsDictionary objectForKey:newtag];
    [button setBackgroundImage:greyImage forState:UIControlStateNormal]; 
    button.selected = YES;
    [self filterTags];
    [self filterViewUp];
}

- (void)saveNote:(NSNotification *)notification
{
    NSDictionary *extraInfo = [notification userInfo];
    Note *note = [extraInfo objectForKey:@"note"];
    NSMutableArray *oldtags = [extraInfo objectForKey:@"oldtags"];
    NSMutableArray *newtags = [note containedTags];
    int pk = [note localId];
    
	if ([note localId] == -1) {
        [self addNewNote:note];
        
        // insert the new note to the top of the note list
        [_notes insertObject:note atIndex:0];
        if (_isFiltering) {
            [_filteredNotes insertObject:note atIndex:0];
        }
        
    } else {
        [self updateNoteText:note];
        
        for (NSString *tag in oldtags) {
            [self deleteOldPairAndTag:tag withNoteID:pk];
        }
        
        for (NSString *tag in newtags) {
            [self saveNewTagAndPair:tag noteID:pk];
        }
        
        // move the updated note to the top of the note list
        [note retain];
        [_notes removeObject:note];
        [_notes insertObject:note atIndex:0];
        
        if (_isFiltering) {
            [_notes removeObject:note];
            [_notes insertObject:note atIndex:0];
        }
        [note release];
	}
    
    if (_author == nil || [_author isEqualToString:@""]) {
        return;
    }
    
    [_loadingIndicator startAnimating];
    [self.view bringSubviewToFront:_loadingIndicator];
    
    if (sqlite3_step(sync_load_synctime_stmt) == SQLITE_ROW) {
        [self setUpdateTime:[self formatDatetimeToServer:[NSString stringWithUTF8String:(char *)sqlite3_column_text(sync_load_synctime_stmt, 0)]]];
    } 
    sqlite3_reset(sync_load_synctime_stmt);
    
    NSLog(@"start synchronize, last updateTime short:%@",_updateTime);
	
    [self syncNewNoteAndModifiedNotesFromLocalToServer];
    [_loadingIndicator stopAnimating];
}

#pragma mark button control

- (void)topLeftButtonClicked:(id)sender {
    if ([self.navigationItem.leftBarButtonItem.title isEqualToString:@"All notes"]) {
        [self showAllNotes];
    } else if ([self.navigationItem.leftBarButtonItem.title isEqualToString:@"Account"]) {
        [self.navigationController presentModalViewController:_settingsNavBarController animated:YES];
    } else {
        // not possible
    }
}

-(void)showSettingsOrAllNotesButton {
    // if already showing all notes, top left button is "settings"
    if (_isFiltering == NO) {
        [self.navigationItem.leftBarButtonItem setTitle:@"Account"];
    } else {
        [self.navigationItem.leftBarButtonItem setTitle:@"All notes"];
    }
}

- (void)showAllNotes {
    _isFiltering = NO;
    [_selectedTags removeAllObjects];
    
    NSArray *allButtons = [_buttonsDictionary allValues];
    for (UIButton *btn in allButtons) {
        btn.selected = NO;
        [btn setBackgroundImage:whiteImage forState:UIControlStateNormal]; 
    }
    
    // restore search bar
    [_mySearchBar resignFirstResponder];
    _mySearchBar.text = @"";
    _mySearchBar.showsCancelButton = NO;
    
    [self showSettingsOrAllNotesButton];
    [_noteTableView reloadData];
    [self arrangeButtons];
}

- (void)addNoteButtonClicked:(id)sender
{
    // restore search bar
    [_mySearchBar resignFirstResponder];
    _mySearchBar.text = @"";
    _mySearchBar.showsCancelButton = NO;
    
    NSMutableString *tempString = [[NSMutableString alloc] initWithString:@""];
    for (NSString *s in _selectedTags) {
        if ([s isEqualToString:@"Untagged"]) {
            // do nothing
        } else {
            [tempString appendString:@" "];
            [tempString appendString:s];
        }
    }
    Note *note = [[Note alloc] initWithPrimaryKey:-1 content:tempString];
    [_detailViewController setEditingNote:note];
    [_detailViewController setNoteIsNew:YES];
    [tempString release];
    [note release];
    [self.navigationController pushViewController:_detailViewController animated:YES];
}
#pragma mark table view initialization

- (id)init 
{
    self = [super init];
    
    _notes = [[NSMutableArray alloc] init];
    _filteredNotes = [[NSMutableArray alloc] init];
    _tags = [[NSMutableArray alloc] init];
    _selectedTags = [[NSMutableArray alloc] init];
    _buttonsDictionary = [[NSMutableDictionary alloc] init];
    _isFiltering = NO;
    _filterIsUp = NO;
    
    [[self navigationItem] setTitle:@"fetchnotes"];
    
    // notification center
    [[NSNotificationCenter defaultCenter] addObserver:self 
                                             selector:@selector(saveNote:) 
                                                 name:SaveNoteNotification 
                                               object:_detailViewController];
    
    [[NSNotificationCenter defaultCenter] addObserver:self 
                                             selector:@selector(redirectWithOneTag:) 
                                                 name:ClickTagInNoteNotification 
                                               object:_detailViewController];
    
    [[NSNotificationCenter defaultCenter] addObserver:self 
                                             selector:@selector(loginHandle:)
                                                 name:LoginNotification 
                                               object:_settingsViewController];
    
    [[NSNotificationCenter defaultCenter] addObserver:self 
                                             selector:@selector(logOutHandle:)
                                                 name:LogOutNotification 
                                               object:_settingsViewController];
    
    [[NSNotificationCenter defaultCenter] addObserver:self 
                                             selector:@selector(startSynchronize:)
                                                 name:StartSyncNotification 
                                               object:_settingsViewController];
    
    
    
    return self;
}

- (id)initWithDatabase:(sqlite3 *)database
{
    self = [self init];
    
    _database = database;
    
    _author = [[NSString alloc] initWithString:@""];
    _privateKey = [[NSString alloc] initWithString:@""];
    _publicKey = [[NSString alloc] initWithString:@""];
    _updateTime = [[NSString alloc] initWithString:DefaultSyncDate];
    
    // TODO can be moved to viewDidLoad if we do not have a sign in/up page
    [self initializeStatements];
    if ([self checkIfUserExists]) {
        _loggedInOnAppStart = YES;
    } else {
        _loggedInOnAppStart = NO;
    }
    
    return self;
}

- (void)didReceiveMemoryWarning
{
    // Releases the view if it doesn't have a superview.
    [super didReceiveMemoryWarning];
}

#pragma mark - View lifecycle

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    [_noteTableView setBounces:NO];
    
    if(_settingsViewController == nil || _settingsNavBarController == nil) {
        _settingsViewController = [[SettingsViewController alloc] init];
        _settingsNavBarController =[[UINavigationController alloc] initWithRootViewController:_settingsViewController];
    }
    
    if (_loggedInOnAppStart) {
        [_settingsViewController logInResultSentBack:YES username:_author email:_email];
    }
    [self loadAllNotes];
    [self loadAllTags];
    
    // backbutton
    UIBarButtonItem *backButton = [[UIBarButtonItem alloc] initWithTitle:@"Back" style: UIBarButtonItemStyleBordered target:nil action:nil];
    [self.navigationItem setBackBarButtonItem:backButton];
    [backButton release];
    
    // logo
    UIImageView *imageView = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 100, 40)];
    imageView.image = [UIImage imageNamed:@"logo.png"];;
    imageView.contentMode = UIViewContentModeScaleAspectFit;
    [self.navigationItem setTitleView:imageView];
    [imageView release];
    self.navigationController.navigationBar.tintColor = [UIColor colorWithRed:65.0/255.0 green:181.0/255.0 blue:254.0/255.0 alpha:1.0];

    
    // settings/all notes button
    UIBarButtonItem *topLeftButton = [[UIBarButtonItem alloc] initWithTitle:@"All Notes" style:UIBarButtonItemStylePlain target:self action:@selector(topLeftButtonClicked:)];          
    [self.navigationItem setLeftBarButtonItem:topLeftButton];
    [topLeftButton release];
    [self showSettingsOrAllNotesButton];
    
    // create a toolbar to have 3 buttons in the right
    TransparentToolbar *tools = [[TransparentToolbar alloc] initWithFrame:CGRectMake(0, 0, 127, 44)]; // 85,44 for 2 buttons
    
    // create the array to hold the buttons, which then gets added to the toolbar
    NSMutableArray* buttons = [[NSMutableArray alloc] initWithCapacity:3];
    
    // create a white tag button
    _filterViewControlButton = [[UIBarButtonItem alloc]
                                initWithImage:[UIImage imageNamed:@"white_tag.png"] style:UIBarButtonItemStyleBordered target:self action:@selector(tagButtonClicked:)];
    [_filterViewControlButton setTintColor:[UIColor colorWithRed:65.0/255.0 green:181.0/255.0 blue:254.0/255.0 alpha:1.0]];
    [_filterViewControlButton setWidth:35];
    [buttons addObject:_filterViewControlButton];
    [_filterViewControlButton release];
    
    // create a spacer
    UIBarButtonItem *bi = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFixedSpace target:nil action:nil];
    [buttons addObject:bi];
    [bi release];
    
    // create a standard "add" button
    bi = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(addNoteButtonClicked:)];
    bi.style = UIBarButtonItemStyleBordered;
    [bi setTintColor:[UIColor colorWithRed:65.0/255.0 green:181.0/255.0 blue:254.0/255.0 alpha:1.0]];
    [buttons addObject:bi];
    [bi release];
    
    // create a spacer
    bi = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFixedSpace target:nil action:nil];
    [buttons addObject:bi];
    [bi release];
    
    // create a standard "refresh" button
    bi = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(refreshButtonClicked:)];
    bi.style = UIBarButtonItemStyleBordered;
    [bi setTintColor:[UIColor colorWithRed:65.0/255.0 green:181.0/255.0 blue:254.0/255.0 alpha:1.0]];
    [buttons addObject:bi];
    [bi release];
    
    // stick the buttons in the toolbar
    [tools setItems:buttons animated:NO];
    
    [buttons release];
    
    // and put the toolbar in the nav bar
    UIBarButtonItem *rightButtons = [[UIBarButtonItem alloc] initWithCustomView:tools];
    self.navigationItem.rightBarButtonItem = rightButtons;
    [rightButtons release];
    [tools release];
    
    
    // detail view controller
    if (_detailViewController == nil) {
        _detailViewController = [[NoteDetailViewController alloc] init];
        
        UIImage *titleImage = [UIImage imageNamed:@"logo.png"];
        UIImageView *imageView = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 100, 40)];
        imageView.image = titleImage;
        imageView.contentMode = UIViewContentModeScaleAspectFit;
        _detailViewController.navigationItem.titleView = imageView;
        [imageView release];
    }
    
    
    
    greyImage = [[UIImage imageNamed:@"darkgrey.png"] retain];
    whiteImage = [[UIImage imageNamed:@"white.jpg"] retain];
    
    
    
    _noteTableView = [[UITableView alloc] initWithFrame:CGRectMake(0, 0, 320, 418) style:UITableViewStylePlain];
    [_noteTableView setDelegate:self];
    [_noteTableView setDataSource:self];
    
    // searchbar
    CGRect frame = CGRectMake(0, 0, 320, 48);
    _mySearchBar = [[UISearchBar alloc] initWithFrame:frame];
    _mySearchBar.autocorrectionType = UITextAutocorrectionTypeNo;
    _mySearchBar.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _mySearchBar.showsCancelButton = NO;
    _mySearchBar.placeholder = @"Type a search term";
    _mySearchBar.delegate = self;
    [_mySearchBar sizeToFit];
    [_mySearchBar setTintColor:[UIColor grayColor]];
    [_noteTableView setTableHeaderView:_mySearchBar];
    [self.view addSubview:_noteTableView];
    
    _tagsFilterView = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 480, 320, 40)];
    [self.view addSubview:_tagsFilterView];
    
    
    // loading indicator
    _loadingIndicator = [[UIActivityIndicatorView alloc]initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
	_loadingIndicator.frame = CGRectMake(0.0, 0.0, 40.0, 40.0);
	_loadingIndicator.center = CGPointMake(160, 120);
	[self.view addSubview: _loadingIndicator];
}

- (void)viewDidUnload
{
    [super viewDidUnload];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [_noteTableView reloadData];
    [self arrangeButtons];
    [self showSettingsOrAllNotesButton];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    _refreshTimer = [NSTimer scheduledTimerWithTimeInterval: SyncTimeInterval
                                                     target: self
                                                   selector: @selector(refreshTimerFired:)
                                                   userInfo: nil
                                                    repeats: YES];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    
    [_refreshTimer invalidate];
    _refreshTimer = nil;
}

- (void)viewDidDisappear:(BOOL)animated
{
    [super viewDidDisappear:animated];
}

- (void)dealloc 
{
    [_detailViewController release];
    [_settingsNavBarController release];
    [_settingsViewController release];
    [_noteTableView release];
    [_tagsFilterView release];
    [_mySearchBar release];
    [_notes release];
    [_filteredNotes release];
    [_tags release];
    [_selectedTags release];
    [_buttonsDictionary release];
    [_publicKey release];
    [_privateKey release];
    [_author release];
    [_email release];
    [_updateTime release];
    [_loadingIndicator release];
    [_refreshTimer invalidate];
    [_filterViewControlButton release];
    
    _detailViewController = nil;
    _settingsNavBarController = nil;
    _settingsViewController = nil;
    _noteTableView = nil;
    _tagsFilterView = nil;
    _mySearchBar = nil;
    _notes = nil;
    _tags = nil;
    _selectedTags = nil;
    _buttonsDictionary = nil;
    _publicKey = nil;
    _privateKey = nil;
    _author = nil;
    _email = nil;
    _updateTime = nil;
    _loadingIndicator = nil;
    _refreshTimer = nil;
    _filterViewControlButton = nil;
    
    [super dealloc];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    return (interfaceOrientation == UIInterfaceOrientationPortrait);
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if (_isFiltering) {
        return [_filteredNotes count];
    }
    return [_notes count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *CellIdentifier = @"Cell";
    
    NoteCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (cell == nil) {
        cell = [[[NoteCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:CellIdentifier] autorelease];
    }
    
    Note *note;
    if (_isFiltering) {
        note = [_filteredNotes objectAtIndex:[indexPath row]];
    } else {
        note = [_notes objectAtIndex:[indexPath row]];
    }
    
    [cell setNote:note];
    
    return cell;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        Note *note;
        if (_isFiltering) {
            note = [_filteredNotes objectAtIndex:[indexPath row]];
            [note retain];
            [_filteredNotes removeObjectAtIndex:[indexPath row]];
            [_notes removeObject:note];
        } else {
            note = [_notes objectAtIndex:[indexPath row]];
            [note retain];
            [_notes removeObjectAtIndex:[indexPath row]];
        }
        
        [tableView deleteRowsAtIndexPaths:[NSArray arrayWithObject:indexPath] withRowAnimation:UITableViewRowAnimationFade];
        [self deleteFromDatabase:note completely:NO];
        [note release];
        
        if (_author == nil || [_author isEqualToString:@""]) {
            return;
        }
        
        [_loadingIndicator startAnimating];
        [self.view bringSubviewToFront:_loadingIndicator];
        
        if (sqlite3_step(sync_load_synctime_stmt) == SQLITE_ROW) {
            [self setUpdateTime:[self formatDatetimeToServer:[NSString stringWithUTF8String:(char *)sqlite3_column_text(sync_load_synctime_stmt, 0)]]];
        } 
        sqlite3_reset(sync_load_synctime_stmt);
        
        NSLog(@"start synchronize, last updateTime short:%@",_updateTime);
        
        [self syncDeletedNotesFromLocalToServer];
        [_loadingIndicator stopAnimating];
    }
}

#pragma mark - Table view delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    Note *note;
    if (_isFiltering) {
        note = [_filteredNotes objectAtIndex:[indexPath row]];
    } else {
        note = [_notes objectAtIndex:[indexPath row]];
    }
    
    [_detailViewController setEditingNote:note];
    [_detailViewController setNoteIsNew:NO];
    
    [self.navigationController pushViewController:_detailViewController animated:YES];
}

#pragma mark UISearchBarDelegate 

- (void)searchBarTextDidBeginEditing:(UISearchBar *)searchBar
{
    _mySearchBar.showsCancelButton = YES;
    if ([_selectedTags count] > 0) {
        if (_filterIsUp) {
            [self filterViewDown];
            [_filterViewControlButton setTintColor:[UIColor colorWithRed:0/255.0 green:167/255.0 blue:255.0/255.0 alpha:1.0]];
        }
        _isFiltering = NO;
        [_selectedTags removeAllObjects];
        [_noteTableView reloadData];
        [self arrangeButtons];
    }
    [self showSettingsOrAllNotesButton];
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText
{
    NSMutableString* trimmedStr = [NSMutableString stringWithString:searchText];
    
    NSUInteger numReplacements;
    int len = [trimmedStr length];
    do {
        NSRange fullRange = NSMakeRange(0, len);
        numReplacements = [trimmedStr replaceOccurrencesOfString:@"  " withString:@" " options:0 range:fullRange];
    } while(numReplacements > 0);
    
    len = [trimmedStr length];
    if (len > 0) {
        [trimmedStr replaceOccurrencesOfString:@" " withString:@"" options:NSCaseInsensitiveSearch range:NSMakeRange(0, 1)];
    }
    NSLog(@"trimmedstring without beginning spaces:%@",trimmedStr);
    
    len = [trimmedStr length];
    if (len > 0) {
        [trimmedStr replaceOccurrencesOfString:@" " withString:@"" options:NSBackwardsSearch range:NSMakeRange(len - 1, 1)];
    }
    
    NSLog(@"trimmedstring without ending spaces:%@",trimmedStr);
    
    if (trimmedStr.length > 0) {
        _isFiltering = YES;
        [_filteredNotes removeAllObjects];
        
        NSArray *splited = [trimmedStr componentsSeparatedByString:@" "];
        for (NSString *word in splited) {
            NSLog(@"split:%@",word);
        }
        BOOL found;
        
        for (Note *nt in _notes) {
            found = true;
            for (NSString *word in splited) {
                if ([[nt noteText] rangeOfString:word options:NSCaseInsensitiveSearch].location == NSNotFound) {
                    found= false;
                    break;
                }
            }
            if (found == true) {
                [_filteredNotes addObject:nt];
            }
        }
        
    } else {
        NSLog(@"displaying all notes for empty query");
        _isFiltering = NO;
    }
    
    [_noteTableView reloadData];
    [self arrangeButtons];
    [self showSettingsOrAllNotesButton];
}

- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar
{
    [self showAllNotes];
}

// called when Search (in our case "Done") button pressed
- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar
{
    [searchBar resignFirstResponder];
    for (id possibleButton in [searchBar subviews]) {
        if ([possibleButton isKindOfClass:[UIButton class]]) {
            [possibleButton setEnabled:YES];
        }
    }
}

@end
