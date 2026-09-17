"! <p class="shorttext synchronized">CFO Brief - language model seam</p>
"! <p>Production: ZCL_CFO_GEMINI_ADAPTER (Gemini via BTP destination).
"! Unit tests pass a local double so the fact guard and fallback can be tested offline.</p>
INTERFACE zif_cfo_llm PUBLIC.

  "! Returns the model's JSON answer.
  METHODS generate
    IMPORTING iv_system      TYPE string
              iv_prompt      TYPE string
    RETURNING VALUE(rv_text) TYPE string
    RAISING   zcx_cfo_error.

  METHODS model
    RETURNING VALUE(rv_model) TYPE string.

ENDINTERFACE.
