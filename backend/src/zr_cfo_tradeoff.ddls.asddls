@AccessControl.authorizationCheck: #CHECK
@EndUserText.label: 'CFO Daily Brief - Advice'
@Metadata.ignorePropagatedAnnotations: true
define view entity ZR_CFO_TradeOff
  as select from ztcfo_tradeoff
  association to parent ZR_CFO_Brief as _Brief on $projection.BriefUuid = _Brief.BriefUuid
{
  key tradeoff_uuid         as TradeoffUuid,
      brief_uuid            as BriefUuid,
      seq                   as Seq,
      kind                  as Kind,
      title                 as Title,
      question              as Question,
      currency              as Currency,
      defer_item            as DeferItem,
      defer_name            as DeferName,
      defer_partner         as DeferPartner,
      @Semantics.amount.currencyCode: 'Currency'
      defer_amount          as DeferAmount,
      defer_note            as DeferNote,
      @Semantics.amount.currencyCode: 'Currency'
      defer_cost            as DeferCost,
      pay_item              as PayItem,
      pay_name              as PayName,
      pay_partner           as PayPartner,
      @Semantics.amount.currencyCode: 'Currency'
      pay_amount            as PayAmount,
      pay_note              as PayNote,
      @Semantics.amount.currencyCode: 'Currency'
      shortfall_before      as ShortfallBefore,
      @Semantics.amount.currencyCode: 'Currency'
      shortfall_after       as ShortfallAfter,
      @Semantics.amount.currencyCode: 'Currency'
      amount                as Amount,
      @Semantics.amount.currencyCode: 'Currency'
      income                as Income,
      annualized_pct        as AnnualizedPct,
      recommendation        as Recommendation,
      detail                as Detail,
      caveat                as Caveat,
      confidence            as Confidence,
      confidence_note       as ConfidenceNote,
      status                as Status,
      case status
        when 'READY'   then 3
        when 'HELD'    then 2
        when 'BLOCKED' then 1
        else 0
      end                   as StatusCriticality,
      action_date           as ActionDate,
      ai_note               as AiNote,
      has_draft             as HasDraft,
      @Semantics.systemDateTime.localInstanceLastChangedAt: true
      local_last_changed_at as LocalLastChangedAt,

      _Brief
}
