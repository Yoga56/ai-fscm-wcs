@AccessControl.authorizationCheck: #CHECK
@EndUserText.label: 'CFO Daily Brief - Advice'
@Metadata.allowExtensions: true
define view entity ZC_CFO_TRADEOFF
  as projection on ZR_CFO_TRADEOFF
{
  key TradeoffUuid,
      BriefUuid,
      Seq,
      Kind,
      Title,
      Question,
      Currency,
      DeferItem,
      DeferName,
      DeferPartner,
      @Semantics.amount.currencyCode: 'Currency'
      DeferAmount,
      DeferNote,
      @Semantics.amount.currencyCode: 'Currency'
      DeferCost,
      PayItem,
      PayName,
      PayPartner,
      @Semantics.amount.currencyCode: 'Currency'
      PayAmount,
      PayNote,
      @Semantics.amount.currencyCode: 'Currency'
      ShortfallBefore,
      @Semantics.amount.currencyCode: 'Currency'
      ShortfallAfter,
      @Semantics.amount.currencyCode: 'Currency'
      Amount,
      @Semantics.amount.currencyCode: 'Currency'
      Income,
      AnnualizedPct,
      Recommendation,
      Detail,
      Caveat,
      Confidence,
      ConfidenceNote,
      Status,
      StatusCriticality,
      ActionDate,
      AiNote,
      HasDraft,
      LocalLastChangedAt,
      _Brief : redirected to parent ZC_CFO_BRIEF
}
