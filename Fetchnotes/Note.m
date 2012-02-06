//
//  Note.m
//  Fetchnotes
// just a test
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

#import "Note.h"

@interface Note(Private)
- (void)findAllTags;
@end

@implementation Note

@synthesize noteText = _noteText;
@synthesize containedTags = _containedTags;
@synthesize localId = _localId;
@synthesize serverId = _serverId;

+ (id)newNoteWithPrimaryKey:(int)primaryKey content:(NSString *)text
{
    Note *newNote = [[self alloc] initWithPrimaryKey:primaryKey content:text]; // ???? why cant autorelease?
    return newNote;
}

- (NSString *)description
{
    NSString *str = [[[NSString alloc] initWithFormat:@"localid: %d, noteText: %@, number of tags: %d, serverid: %@",_localId, _noteText, [_containedTags count], _serverId] autorelease];
    return str;
}

- (id)initWithPrimaryKey:(NSInteger)primaryKey content:(NSString *)text
{
    self = [super init];
    
    if (!self) {
        return nil;
    }
    
    [self setNoteText:text];
    [self setServerId:@""];
    _localId = primaryKey;
    _containedTags = [[NSMutableArray alloc] init];
    
    if (![text isEqualToString:@""]) {
        [self findAllTags];
    }
    
    return self;
}

- (void)findAllTags 
{
    [_containedTags removeAllObjects];
    
    NSError *error = NULL;	
	NSRegularExpression *regex;
    NSString *tempText = [[_noteText mutableCopy] autorelease]; // ???? autorelease here?
    
    // strip url
    regex= [NSRegularExpression regularExpressionWithPattern:@"(http|https)\\://[A-Z0-9\\-\\.]+\\.[A-Z]{2,4}(/\\S*)?" options:NSRegularExpressionCaseInsensitive error:&error]; 
    tempText = [regex stringByReplacingMatchesInString:tempText options:0 range:NSMakeRange(0, [tempText length]) withTemplate:@""];
//    NSLog(@"text after stripurl: %@",tempText);
    
    // strip email
    regex = [NSRegularExpression regularExpressionWithPattern:@"[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,4}" options:NSRegularExpressionCaseInsensitive error:&error]; 
    tempText = [regex stringByReplacingMatchesInString:tempText options:0 range:NSMakeRange(0, [tempText length]) withTemplate:@""];
//    NSLog(@"text after stripemail: %@",tempText);
    
    NSArray *matches;
    // find all @ tags
    regex = [NSRegularExpression regularExpressionWithPattern:@"@[0-9A-Za-z_]+" options:NSRegularExpressionCaseInsensitive error:&error];
    matches = [regex matchesInString:tempText
                             options:0
                               range:NSMakeRange(0, [tempText length])];
    
    for (NSTextCheckingResult *match in matches) {
        NSRange matchRange = [match range];
        NSMutableString *substring = [[[tempText substringWithRange:matchRange] lowercaseString] mutableCopy];
//        NSLog(@"Extracted atTag: %@",substring);
        [_containedTags addObject:substring];
        [substring release];
    }
    
    // find all # tags
    regex = [NSRegularExpression regularExpressionWithPattern:@"#[0-9A-Za-z_]+" options:NSRegularExpressionCaseInsensitive error:&error];
    matches = [regex matchesInString:tempText
                             options:0
                               range:NSMakeRange(0, [tempText length])];
    
    for (NSTextCheckingResult *match in matches) {
        NSRange matchRange = [match range];
        NSMutableString *substring = [[[tempText substringWithRange:matchRange] lowercaseString] mutableCopy];
//        NSLog(@"Extracted hashtag: %@",substring);
        [_containedTags addObject:substring];
        [substring release];
    }
    
    if ([_containedTags count] == 0) {
        [_containedTags addObject:@"Untagged"];
    }
}

- (void)updateText:(NSString *)newText
{
    [self setNoteText:newText];
    [self findAllTags];
}

- (void)dealloc
{
    [_noteText release];
    [_containedTags release];
    [_serverId release];
    [super dealloc];
}

@end
