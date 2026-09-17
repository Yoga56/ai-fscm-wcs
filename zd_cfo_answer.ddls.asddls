@EndUserText.label: 'CFO Brief - copilot answer'
define abstract entity ZD_CFO_Answer
{
  Answer    : abap.char(1333);
  FollowUps : abap.char(1000);
  Engine    : abap.char(6);
  ModelUsed : abap.char(60);
  ErrorText : abap.char(255);
}
