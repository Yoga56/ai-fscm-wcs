#!/usr/bin/env python3
"""Builds app/cfobrief/webapp/localService/metadata.xml from the CDS/BDEF sources.

Only needed until the service binding ZUI_CFO_BRIEF_O4 is published - then save the
real $metadata over the generated file. Run: python3 tools/gen_metadata.py
"""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "backend" / "src"
OUT = ROOT / "app" / "cfobrief" / "webapp" / "localService" / "metadata.xml"
NS = "com.sap.gateway.srvd.zui_cfo_brief.v0001"

ENTITIES = [  # set name, interface view, table, key
    ("Brief", "zr_cfo_brief", "ztcfo_brief", "BriefUuid"),
    ("RunwayDay", "zr_cfo_runwayday", "ztcfo_runway", "RunwayUuid"),
    ("Risk", "zr_cfo_risk", "ztcfo_risk", "RiskUuid"),
    ("TradeOff", "zr_cfo_tradeoff", "ztcfo_tradeoff", "TradeoffUuid"),
    ("ActionDraft", "zr_cfo_actiondraft", "ztcfo_action", "ActionUuid"),
]
COMPUTED = {"LiquidityCriticality": "Edm.Int32", "StatusCriticality": "Edm.Int32"}


def edm(abap):
    abap = abap.strip()
    m = re.match(r"abap\.char\((\d+)\)", abap)
    if m:
        return f'Type="Edm.String" MaxLength="{m.group(1)}"'
    m = re.match(r"abap\.(curr|dec)\((\d+),(\d+)\)", abap)
    if m:
        return f'Type="Edm.Decimal" Precision="{m.group(2)}" Scale="{m.group(3)}"'
    m = re.match(r"abap\.numc\((\d+)\)", abap)
    if m:
        return f'Type="Edm.String" MaxLength="{m.group(1)}"'
    return {
        "sysuuid_x16": 'Type="Edm.Guid"',
        "abap.dats": 'Type="Edm.Date"',
        "abap.int4": 'Type="Edm.Int32"',
        "abap.int1": 'Type="Edm.Byte"',
        "abap.cuky": 'Type="Edm.String" MaxLength="5"',
        "abap_boolean": 'Type="Edm.Boolean"',
        "abap.string(0)": 'Type="Edm.String"',
        "timestampl": 'Type="Edm.DateTimeOffset" Precision="7"',
        "abp_creation_tstmpl": 'Type="Edm.DateTimeOffset" Precision="7"',
        "abp_lastchange_tstmpl": 'Type="Edm.DateTimeOffset" Precision="7"',
        "abp_locinst_lastchange_tstmpl": 'Type="Edm.DateTimeOffset" Precision="7"',
        "abp_creation_user": 'Type="Edm.String" MaxLength="12"',
        "abp_lastchange_user": 'Type="Edm.String" MaxLength="12"',
    }[abap]


def table_types(table):
    src = (SRC / "db" / f"{table}.tabl.asddls").read_text()
    return dict(re.findall(r"^\s*(?:key\s+)?(\w+)\s*:\s*([\w.(),]+)", src, re.M))


def view_fields(view):
    src = (SRC / "cds" / f"{view}.ddls.asddls").read_text()
    body = src[src.index("{", src.index("define")) + 1:]
    return re.findall(r"^\s*(?:key\s+)?(\w+)?\s*as\s+(\w+)", body, re.M), body


def abstract(name):
    src = (SRC / "cds" / f"{name.lower()}.ddls.asddls").read_text()
    return re.findall(r"^\s*(\w+)\s*:\s*([\w.(),]+);", src, re.M)


lines = ['<?xml version="1.0" encoding="utf-8"?>',
         '<edmx:Edmx Version="4.0" xmlns:edmx="http://docs.oasis-open.org/odata/ns/edmx">',
         '  <edmx:DataServices>',
         f'    <Schema Namespace="{NS}" Alias="SAP__self" xmlns="http://docs.oasis-open.org/odata/ns/edm">']

for set_name, view, table, key in ENTITIES:
    types = table_types(table)
    pairs, body = view_fields(view)
    lines.append(f'      <EntityType Name="{set_name}Type">')
    lines.append(f'        <Key><PropertyRef Name="{key}"/></Key>')
    for col, alias in pairs:
        if alias.startswith("_"):
            continue
        if alias in COMPUTED or not col:
            lines.append(f'        <Property Name="{alias}" Type="{COMPUTED.get(alias, "Edm.Int32")}"/>')
            continue
        nullable = ' Nullable="false"' if alias == key else ""
        lines.append(f'        <Property Name="{alias}" {edm(types[col])}{nullable}/>')
    if set_name == "Brief":
        for child in ("RunwayDay", "Risk", "TradeOff", "ActionDraft"):
            lines.append(f'        <NavigationProperty Name="_{child}" Type="Collection({NS}.{child}Type)" Partner="_Brief"/>')
    else:
        lines.append(f'        <NavigationProperty Name="_Brief" Type="{NS}.BriefType" Nullable="false" Partner="_{set_name}">')
        lines.append('          <ReferentialConstraint Property="BriefUuid" ReferencedProperty="BriefUuid"/>')
        lines.append('        </NavigationProperty>')
    lines.append('      </EntityType>')

for ct in ("ZD_CFO_SimDay", "ZD_CFO_Answer"):
    lines.append(f'      <ComplexType Name="{ct}">')
    for name, typ in abstract(ct):
        lines.append(f'        <Property Name="{name}" {edm(typ)}/>')
    lines.append('      </ComplexType>')


def action(name, bound, params, returns, collection_bound=False, self_result=False):
    it = f"Collection({NS}.{bound}Type)" if collection_bound else f"{NS}.{bound}Type"
    esp = ' EntitySetPath="_it"' if self_result else ""
    out = [f'      <Action Name="{name}" IsBound="true"{esp}>',
           f'        <Parameter Name="_it" Type="{it}" Nullable="false"/>']
    for pname, ptype in params:
        out.append(f'        <Parameter Name="{pname}" {edm(ptype)}/>')
    out.append(f'        <ReturnType Type="{returns}" Nullable="false"/>')
    out.append('      </Action>')
    return out


lines += action("generateBrief", "Brief", abstract("ZD_CFO_GenParam"), f"{NS}.BriefType", True, True)
lines += action("refreshAi", "Brief", [], f"{NS}.BriefType", self_result=True)
lines += action("simulate", "Brief", abstract("ZD_CFO_SimParam"), f"Collection({NS}.ZD_CFO_SimDay)")
lines += action("askCopilot", "Brief", abstract("ZD_CFO_AskParam"), f"{NS}.ZD_CFO_Answer")
lines += action("proposeRunExceptions", "Brief", [], f"{NS}.BriefType", self_result=True)
lines += action("draftCollectionNotice", "Risk", [], f"{NS}.RiskType", self_result=True)
lines += action("proposeDecision", "TradeOff", [], f"{NS}.TradeOffType", self_result=True)
lines += action("submitForApproval", "ActionDraft", [], f"{NS}.ActionDraftType", self_result=True)
lines += action("approve", "ActionDraft", abstract("ZD_CFO_DecisionParam"), f"{NS}.ActionDraftType", self_result=True)
lines += action("reject", "ActionDraft", abstract("ZD_CFO_DecisionParam"), f"{NS}.ActionDraftType", self_result=True)

lines.append('      <EntityContainer Name="Container">')
for set_name, *_ in ENTITIES:
    lines.append(f'        <EntitySet Name="{set_name}" EntityType="{NS}.{set_name}Type">')
    if set_name == "Brief":
        for child in ("RunwayDay", "Risk", "TradeOff", "ActionDraft"):
            lines.append(f'          <NavigationPropertyBinding Path="_{child}" Target="{child}"/>')
    else:
        lines.append('          <NavigationPropertyBinding Path="_Brief" Target="Brief"/>')
    lines.append('        </EntitySet>')
lines += ['      </EntityContainer>', '    </Schema>', '  </edmx:DataServices>', '</edmx:Edmx>', '']

OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_text("\n".join(lines))
print(f"wrote {OUT.relative_to(ROOT)}")
