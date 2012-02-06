//
//  SettingsViewController.m
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

#import "SettingsViewController.h"
#import "Constants.h"

@implementation SettingsViewController
@synthesize loggedIn = _loggedIn;

- (void)DisplayAlert:(NSString *)title andMessage:(NSString *)message 
{
	UIAlertView* alert = [[UIAlertView alloc] initWithTitle:title message:message delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
	[alert show];
	[alert release];
}

- (void)logOutResultSentBack:(BOOL)success
{
    [_loadingIndicator stopAnimating];
    if (success) {
        [_firstField setText:@""];
        [_firstField setEnabled:YES];
        [_secondeField setText:@""];
        [_secondeField setSecureTextEntry:YES];
        [_secondeField setEnabled:YES];
        [_loginButton setTitle:@"Log In" forState:UIControlStateNormal];
        _loggedIn = NO;
        [(UITableView *)self.view reloadData];
    } else {
        [self DisplayAlert:@"Sorry" andMessage:[NSString stringWithFormat:@"Fail to sign out. Try again!"]];   
    }
}

- (void)logInResultSentBack:(BOOL)success username:(NSString *)name email:(NSString *)email
{
    [_loadingIndicator stopAnimating];
    if (success) {
//        [self DisplayAlert:@"Congrats" andMessage:[NSString stringWithFormat:@"You just logged in!"]];
        [_firstField setText:name];
        [_firstField setEnabled:NO];
        [_secondeField setText:email];
        [_secondeField setSecureTextEntry:NO];
        [_secondeField setEnabled:NO];
        [_loginButton setTitle:@"Sign Out" forState:UIControlStateNormal];
        _loggedIn = YES;
        [(UITableView *)self.view reloadData];
        NSNotification *notif = [NSNotification notificationWithName:StartSyncNotification object:self];
        [[NSNotificationCenter defaultCenter] postNotification:notif];
    } else {
        [self DisplayAlert:@"Sorry" andMessage:[NSString stringWithFormat:@"Login error. Try again!"]];   
    }
}

- (void)doneButtonHit:(id)sender {
    [self.navigationController dismissModalViewControllerAnimated:YES];
}

- (void)logInOutButtonClicked:(id)sender
{
    if (_loggedIn) {
        [_loadingIndicator startAnimating];
        [self.view bringSubviewToFront:_loadingIndicator];
        NSNotification *notif = [NSNotification notificationWithName:LogOutNotification object:self];
        [[NSNotificationCenter defaultCenter] postNotification:notif];
        return;
    }
    
    if ([_firstField text] == nil || [[_firstField text] isEqualToString:@""]) {
        [self DisplayAlert:@"Sorry!" andMessage:[NSString stringWithFormat:@"Please provide username or email!"]];
        return;
    } else if ([_secondeField text] == nil || [[_secondeField text] isEqualToString:@""]) {
        [self DisplayAlert:@"Sorry!" andMessage:[NSString stringWithFormat:@"Please provide password!"]];
        return;
    }
    
    [_loadingIndicator startAnimating];
    [self.view bringSubviewToFront:_loadingIndicator];
    
    NSDictionary *extraInfo = [[[NSDictionary alloc] initWithObjectsAndKeys:[_firstField text], @"name", [_secondeField text], @"password", nil] autorelease];
    NSNotification *notif = [NSNotification notificationWithName:LoginNotification object:self userInfo:extraInfo];
    [[NSNotificationCenter defaultCenter] postNotification:notif];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
    [textField resignFirstResponder];
    
    if ([_firstField text] == nil || [[_firstField text] isEqualToString:@""] || [_secondeField text] == nil || [[_secondeField text] isEqualToString:@""]) {
        return YES;
    }
    [self logInOutButtonClicked:nil];
    return YES;
}

- (id)init
{
    self = [super initWithStyle:UITableViewStyleGrouped];
    
    _firstField = [[UITextField alloc] initWithFrame:CGRectMake(20, 10, 300, 50)];
    _secondeField = [[UITextField alloc] initWithFrame:CGRectMake(20, 10, 300, 50)];
    
    return self;
}

- (id)initWithStyle:(UITableViewStyle)style
{
    return [self init];
}

- (void)didReceiveMemoryWarning
{
    // Releases the view if it doesn't have a superview.
    [super didReceiveMemoryWarning];
    
    // Release any cached data, images, etc that aren't in use.
}

#pragma mark - View lifecycle

- (void)viewDidLoad
{
    [super viewDidLoad];
    [self setTitle:@"Account"];

    [_firstField setDelegate:self]; 
    _firstField.autocorrectionType = UITextAutocorrectionTypeNo;
    _firstField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    [_secondeField setDelegate:self];   
    _secondeField.autocorrectionType = UITextAutocorrectionTypeNo;
    _secondeField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    
    _loginButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    [_loginButton setTitle:@"Login" forState:UIControlStateNormal];
    [_loginButton addTarget:self action:@selector(logInOutButtonClicked:) forControlEvents:UIControlEventTouchUpInside];
    _loginButton.frame = CGRectMake(10, 200, 300, 40);
    [self.view addSubview:_loginButton];
    
    self.navigationController.navigationBar.tintColor = [UIColor colorWithRed:65.0/255.0 green:181.0/255.0 blue:254.0/255.0 alpha:1.0];
    
    UIBarButtonItem *btn = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(doneButtonHit:)];
    self.navigationItem.leftBarButtonItem = btn;
    [btn release];
    
    _loadingIndicator = [[UIActivityIndicatorView alloc]initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
	_loadingIndicator.frame = CGRectMake(0.0, 0.0, 40.0, 40.0);
	_loadingIndicator.center = CGPointMake(160, 120);
	[self.view addSubview: _loadingIndicator];
}

- (void)viewDidUnload
{
    [super viewDidUnload];
    // Release any retained subviews of the main view.
    // e.g. self.myOutlet = nil;
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    if (!_loggedIn) {
        _secondeField.secureTextEntry = YES;
        [_loginButton setTitle:@"Log In" forState:UIControlStateNormal];
    } else {
        _secondeField.secureTextEntry = NO;
        [_loginButton setTitle:@"Sign Out" forState:UIControlStateNormal];

    }
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
}

- (void)viewDidDisappear:(BOOL)animated
{
    [super viewDidDisappear:animated];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    return (interfaceOrientation == UIInterfaceOrientationPortrait);
}

- (void)dealloc 
{
    [_firstField release];
    [_secondeField release];
    [_loginButton release];
    [_loadingIndicator release];
    
    _firstField = nil;
    _secondeField = nil;
    _loginButton = nil;
    _loadingIndicator = nil;
    
    [super dealloc];
}

#pragma mark - Table view data source

-(UITableViewCell *)configCellWithtextfield:(UITextField *)tf placeholder:(NSString *)holder {
    static NSString *CellIdentifier = @"TitleCell";
    
    UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (cell == nil) {
        cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:CellIdentifier] autorelease];
    }
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.frame = CGRectMake(20,0,320,44);
    
    [tf setPlaceholder:holder];
    [cell addSubview:tf];
    
    return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *CellIdentifier = @"Cell";
    
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (cell == nil) {
        cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:CellIdentifier] autorelease];
    }
    
    if (_loggedIn == YES) {
        switch (indexPath.section) {
            case 0:
                cell = [self configCellWithtextfield:_firstField placeholder:@"fetch"];
                break;
            case 1:
                cell = [self configCellWithtextfield:_secondeField placeholder:@"fetch@fetchnotes.com"];
                break;
            default:
                break;
        }
    } else {
        switch (indexPath.section) {
            case 0:
                cell = [self configCellWithtextfield:_firstField placeholder:@"username or email"];
                break;
            case 1:
                cell = [self configCellWithtextfield:_secondeField placeholder:@"password"];
                break;
            default:
                break;
        }
    }
    
    return cell;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    if (_loggedIn == YES) {
        if (section == 0) {
            return @"Username";
        } else if (section == 1) {
            return @"Email";
        }
    } else {
        if (section == 0) {
            return @"Username or Email";
        } else if (section == 1) {
            return @"Password";
        }
    }
    
    return 0;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return 1;
}

#pragma mark - Table view delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    // Navigation logic may go here. Create and push another view controller.
    /*
     <#DetailViewController#> *detailViewController = [[<#DetailViewController#> alloc] initWithNibName:@"<#Nib name#>" bundle:nil];
     // ...
     // Pass the selected object to the new view controller.
     [self.navigationController pushViewController:detailViewController animated:YES];
     [detailViewController release];
     */
}

@end
