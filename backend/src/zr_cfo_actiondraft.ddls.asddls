@AccessControl.authorizationCheck: #CHECK
@EndUserText.label: 'CFO Daily Brief - Action draft'
@Metadata.ignorePropagatedAnnotations: true
define view entity ZR_CFO_ActionDraft
  as select from ztcfo_action
  association to parent ZR_CFO_Brief as _Brief on $projection.BriefUuid = _Brief.BriefUuid
{
  key action_uuid           as ActionUuid,
      brief_uuid            as BriefUuid,
      action_type           as ActionType,
      source_kind           as SourceKind,
      source_uuid           as SourceUuid,
      recipient             as Recipient,
      subject               as Subject,
      body                  as Body,
      internal_note         as InternalNote,
      currency              as Currency,
      @Semantics.amount.currencyCode: 'Currency'
      amount                as Amount,
      status                as Status,
      case status
        when 'APPROVED' then 3
        when 'ROUTED'   then 2
        when 'REJECTED' then 1
        else 0
      end                   as StatusCriticality,
      engine                as Engine,
      routed_to             as RoutedTo,
      routed_at             as RoutedAt,
      decided_by            as DecidedBy,
      decided_at            as DecidedAt,
      decision_note         as DecisionNote,
      @Semantics.user.createdBy: true
      created_by            as CreatedBy,
      @Semantics.systemDateTime.createdAt: true
      created_at            as CreatedAt,
      @Semantics.user.lastChangedBy: true
      last_changed_by       as LastChangedBy,
      @Semantics.systemDateTime.lastChangedAt: true
      last_changed_at       as LastChangedAt,
      @Semantics.systemDateTime.localInstanceLastChangedAt: true
      local_last_changed_at as LocalLastChangedAt,

      _Brief
}
