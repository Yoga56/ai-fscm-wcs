@AccessControl.authorizationCheck: #CHECK
@EndUserText.label: 'CFO Daily Brief - Ranked risk'
@Metadata.allowExtensions: true
define view entity ZC_CFO_RISK
  as projection on ZR_CFO_RISK
{
  key RiskUuid,
      BriefUuid,
      RiskRank,
      RiskType,
      Epard,
      Reference,
      PartnerName,
      Title,
      Detail,
      Currency,
      @Semantics.amount.currencyCode: 'Currency'
      Exposure,
      Probability,
      FloorWeight,
      @Semantics.amount.currencyCode: 'Currency'
      Score,
      Criticality,
      Recommendation,
      RecommendationText,
      AiNote,
      DueBy,
      Status,
      HasDraft,
      LocalLastChangedAt,
      _Brief : redirected to parent ZC_CFO_BRIEF
}
