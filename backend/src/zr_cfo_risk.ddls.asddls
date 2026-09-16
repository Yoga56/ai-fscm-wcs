@AccessControl.authorizationCheck: #CHECK
@EndUserText.label: 'CFO Daily Brief - Ranked risk'
@Metadata.ignorePropagatedAnnotations: true
define view entity ZR_CFO_Risk
  as select from ztcfo_risk
  association to parent ZR_CFO_Brief as _Brief on $projection.BriefUuid = _Brief.BriefUuid
{
  key risk_uuid             as RiskUuid,
      brief_uuid            as BriefUuid,
      risk_rank             as RiskRank,
      risk_type             as RiskType,
      epard                 as Epard,
      reference             as Reference,
      partner_name          as PartnerName,
      title                 as Title,
      detail                as Detail,
      currency              as Currency,
      @Semantics.amount.currencyCode: 'Currency'
      exposure              as Exposure,
      probability           as Probability,
      floor_weight          as FloorWeight,
      @Semantics.amount.currencyCode: 'Currency'
      score                 as Score,
      criticality           as Criticality,
      recommendation        as Recommendation,
      recommendation_text   as RecommendationText,
      ai_note               as AiNote,
      due_by                as DueBy,
      status                as Status,
      has_draft             as HasDraft,
      @Semantics.systemDateTime.localInstanceLastChangedAt: true
      local_last_changed_at as LocalLastChangedAt,

      _Brief
}
