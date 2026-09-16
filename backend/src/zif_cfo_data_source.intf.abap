"! <p class="shorttext synchronized">CFO Brief - ledger data access (LIVE or DEMO)</p>
"! <p>Everything the engine reads from core FI/MM goes through this interface.
"! ZCL_CFO_SOURCE_LIVE reads released CDS views; ZCL_CFO_SOURCE_DEMO reads the
"! seeded demo tables. A tier-2 implementation (e.g. reading the real F110
"! proposal) can be plugged in via ZCL_CFO_DATA_LOADER=>SET_SOURCE.</p>
INTERFACE zif_cfo_data_source PUBLIC.

  "! Cash at bank at the end of the key date.
  METHODS bank_balance
    IMPORTING is_config        TYPE zif_cfo_types=>ty_config
              iv_key_date      TYPE d
    RETURNING VALUE(rv_amount) TYPE zif_cfo_types=>amount
    RAISING   zcx_cc_error.

  "! Open customer and supplier items (amount positive in the item's direction).
  METHODS open_items
    IMPORTING is_config       TYPE zif_cfo_types=>ty_config
              iv_key_date     TYPE d
    RETURNING VALUE(rt_items) TYPE zif_cfo_types=>tt_open_item
    RAISING   zcx_cc_error.

  "! Invoices cleared within the configured look-back.
  METHODS history
    IMPORTING is_config         TYPE zif_cfo_types=>ty_config
              iv_key_date       TYPE d
    RETURNING VALUE(rt_history) TYPE zif_cfo_types=>tt_history
    RAISING   zcx_cc_error.

  "! Purchase-order spend by plant in 30-day windows (0 = most recent).
  METHODS spend
    IMPORTING is_config       TYPE zif_cfo_types=>ty_config
              iv_key_date     TYPE d
    RETURNING VALUE(rt_spend) TYPE zif_cfo_types=>tt_spend
    RAISING   zcx_cc_error.

ENDINTERFACE.
