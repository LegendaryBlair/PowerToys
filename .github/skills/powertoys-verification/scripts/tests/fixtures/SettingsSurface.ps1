#requires -Version 7.2
param([Parameter(Mandatory)][string]$ReadyPath,[switch]$Simple)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationFramework
[xml]$xaml=@'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Owned harness Settings fixture" Width="480" Height="420" Left="260" Top="180">
  <Grid>
    <Grid.ColumnDefinitions><ColumnDefinition Width="150"/><ColumnDefinition/></Grid.ColumnDefinitions>
    <ListBox x:Name="Navigation" AutomationProperties.AutomationId="Navigation" SelectedIndex="0">
      <ListBoxItem AutomationProperties.AutomationId="DashboardNavItem">Home fixture</ListBoxItem>
      <ListBoxItem AutomationProperties.AutomationId="FixtureNavItem">Other fixture</ListBoxItem>
    </ListBox>
    <ScrollViewer Grid.Column="1" x:Name="ContentScroll" AutomationProperties.AutomationId="ContentScroll">
      <StackPanel>
        <Expander x:Name="Details" Header="Details" IsExpanded="True" AutomationProperties.AutomationId="Details">
          <TextBlock Text="Owned synthetic content"/>
        </Expander>
        <Border Height="950" Background="LightBlue"/>
        <TextBlock Text="End of scroll fixture"/>
      </StackPanel>
    </ScrollViewer>
  </Grid>
</Window>
'@
$window=[Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new($xaml))
$welcome=$null
if(-not $Simple){
    $welcome=[Windows.Window]::new()
    $welcome.Title='Owned harness Welcome sibling';$welcome.Width=280;$welcome.Height=150
    $welcome.Left=760;$welcome.Top=200
    $welcome.Content='Do not close a pre-existing sibling.'
    $welcome.Show()
}
$window.Add_ContentRendered({
    $window.FindName('ContentScroll').ScrollToVerticalOffset(160)
    $window.Dispatcher.BeginInvoke([Action]{
        $hwnd=[Windows.Interop.WindowInteropHelper]::new($window).Handle.ToInt64()
        $sibling=if($welcome){[Windows.Interop.WindowInteropHelper]::new($welcome).Handle.ToInt64()}else{0L}
        [IO.File]::WriteAllText($ReadyPath,(ConvertTo-Json @{Hwnd=$hwnd;Sibling=$sibling;ProcessId=$PID}))
    },[Windows.Threading.DispatcherPriority]::ApplicationIdle)|Out-Null
})
try{$window.ShowDialog()|Out-Null}
finally{if($welcome){$welcome.Close()}}
