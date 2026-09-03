from datetime import date

from app.routers.finance import _detect_card_movements, _parse_card_amount


def test_installment_row_uses_written_date_and_detects_installment():
    text = "02-Mar-26 MERPAGO*LATARIMA 05/06 03629 6.474,94"

    items, _ = _detect_card_movements(text, "2026-08")

    assert len(items) == 1
    assert items[0].date == date(2026, 3, 2)
    assert items[0].amount == 6474.94
    assert items[0].installments == "5/6"
    assert items[0].description == "MERPAGO*LATARIMA"


def test_splits_three_transactions_joined_in_one_pdf_line():
    text = (
        "14-Jul-26 MODOQRI*NATURAL LI 04880 15.328,87 "
        "16-Jul-26 MERPAGO*OPEN25 03443 2.700,00 "
        "16-Jul-26 NUEVA FARMACIA SANTA R 08951 19.435,17"
    )

    items, _ = _detect_card_movements(text, "2026-08")

    assert [(item.date, item.amount) for item in items] == [
        (date(2026, 7, 14), 15328.87),
        (date(2026, 7, 16), 2700.00),
        (date(2026, 7, 16), 19435.17),
    ]
    assert [item.description for item in items] == [
        "MODOQRI*NATURAL LI",
        "MERPAGO*OPEN25",
        "NUEVA FARMACIA SANTA R",
    ]
    assert all(item.observation is None for item in items)


def test_splits_transactions_and_removes_consumption_header():
    text = "\n".join(
        [
            "DETALLE DEL CONSUMO FECHA REFERENCIA COMPROBANTE DÓLARES COMPRAS DEL MES",
            "01-Jul-26 NUEVA FARMACIA SANTA R 03965 9.772,34 03-Jul-26 MARKET AVENIDA STA. FE 09920 9.448,50",
            "DETALLE DEL CONSUMO FECHA REFERENCIA COMPROBANTE DÓLARES 03-Jul-26 TOMASSO 01234 14.999,00",
        ]
    )

    items, _ = _detect_card_movements(text, "2026-08")

    assert [(item.date, item.amount) for item in items] == [
        (date(2026, 7, 1), 9772.34),
        (date(2026, 7, 3), 9448.50),
        (date(2026, 7, 3), 14999.00),
    ]
    assert items[0].description == "NUEVA FARMACIA SANTA R"
    assert items[1].description == "MARKET AVENIDA STA. FE"
    assert items[2].description == "TOMASSO"
    assert "DETALLE" not in items[2].description


def test_only_imports_ars_rows_inside_detail_sections():
    text = """
    PAGO MINIMO LIMITES
    En pesos $ 172.700,00
    De compras en un pago y en cuotas $ 7.000.000,00
    SALDO ANTERIOR 2.702.838,17 78,40
    06-Jul-26 SU PAGO -2.676.400,00 -2.676.400,00
    PERCEPCION IVA DTO 354/18 8.455,32
    TOTAL A PAGAR 1.721.818,60 105,49
    DETALLE DEL CONSUMO
    FECHA REFERENCIA COMPROBANTE PESOS DOLARES
    COMPRAS DEL MES
    14-Jul-26 MODOQRI*NATURAL LI 04880 15.328,87
    16-Jul-26 MERPAGO*OPEN25 03443 2.700,00
    DEBITOS AUTOMATICOS
    16-Jul-26 PERSFLOW25810002 07/26 06586 26.076,42
    CUOTAS DEL MES
    02-Mar-26 MERPAGO*LATARIMA 05/06 03629 6.474,94
    SUBTOTAL 1.613.231,04 45,84
    COMPRAS DEL MES
    25-Jun-26 OPENAI *CHATGPT (USA,USD, 20,00) 00531 20,00
    02-Jul-26 WL *STEAM PURCHA(USA,USD, -7,19) 00902 -7,19
    03-Jul-26 TOMASSO 09921 14.999,00
    TOTAL ADICIONAL DE VELEZ OSORIO,JOSE M 84.219,84 59,65
    TOTAL A PAGAR 1.721.818,60 105,49
    Cuotas a vencer Agosto-26 $ 248.085,14
    OPCIONES DE FINANCIACION TNA 86,750% TEA 131,610%
    """

    items, warnings = _detect_card_movements(text, "2026-08")

    assert [(item.description, item.amount) for item in items] == [
        ("MODOQRI*NATURAL LI", 15328.87),
        ("MERPAGO*OPEN25", 2700.00),
        ("PERSFLOW25810002 07/26", 26076.42),
        ("MERPAGO*LATARIMA", 6474.94),
        ("TOMASSO", 14999.00),
    ]
    assert items[2].installments is None
    assert items[3].installments == "5/6"
    assert all(item.currency == "ARS" for item in items)
    assert any("moneda extranjera" in warning for warning in warnings)
    assert any("importe negativo" in warning for warning in warnings)
    assert not any("172.700" in item.raw_text or "7.000.000" in item.raw_text for item in items)


def test_same_merchant_date_and_amount_are_kept_when_receipts_differ():
    text = """
    DETALLE DEL CONSUMO
    COMPRAS DEL MES
    13-Jul-26 EMOVA SUBTE 09440 1.621,00
    13-Jul-26 EMOVA SUBTE 09441 1.621,00
    TOTAL ADICIONAL DE PERSONA 3.242,00
    """

    items, _ = _detect_card_movements(text, "2026-08")

    assert len(items) == 2
    assert [item.amount for item in items] == [1621.00, 1621.00]
    assert [item.raw_text for item in items] == [
        "13-Jul-26 EMOVA SUBTE 09440 1.621,00",
        "13-Jul-26 EMOVA SUBTE 09441 1.621,00",
    ]


def test_steam_name_is_not_confused_with_tea_rate():
    text = """
    DETALLE DEL CONSUMO
    COMPRAS DEL MES
    10-Jul-26 STEAM ARGENTINA 00491 17.999,00
    TOTAL A PAGAR 17.999,00
    """

    items, _ = _detect_card_movements(text, "2026-08")

    assert len(items) == 1
    assert items[0].description == "STEAM ARGENTINA"
    assert items[0].amount == 17999.00


def test_negative_amount_keeps_its_sign_and_is_not_imported_as_expense():
    assert _parse_card_amount("-7,19") == -7.19

    text = """
    DETALLE DEL CONSUMO
    COMPRAS DEL MES
    02-Jul-26 DEVOLUCION LOCAL 00902 -7,19
    TOTAL A PAGAR 0,00
    """
    items, warnings = _detect_card_movements(text, "2026-08")

    assert items == []
    assert any("importe negativo" in warning for warning in warnings)


def test_exact_repeated_row_is_hidden_but_not_a_different_receipt():
    text = """
    DETALLE DEL CONSUMO
    COMPRAS DEL MES
    13-Jul-26 EMOVA SUBTE 09440 1.621,00
    13-Jul-26 EMOVA SUBTE 09440 1.621,00
    13-Jul-26 EMOVA SUBTE 09441 1.621,00
    TOTAL A PAGAR 3.242,00
    """

    items, warnings = _detect_card_movements(text, "2026-08")

    assert len(items) == 2
    assert any("exactamente repetida" in warning for warning in warnings)


def test_flattened_sections_keep_each_row_in_its_own_section():
    text = (
        "DETALLE DEL CONSUMO COMPRAS DEL MES "
        "30-Jun-26 MERPAGO*MELI 06/26 00978 3.490,00 "
        "DEBITOS AUTOMATICOS "
        "16-Jul-26 PERSFLOW25810002 07/26 06586 26.076,42 "
        "CUOTAS DEL MES "
        "02-Mar-26 MERPAGO*LATARIMA 05/06 03629 6.474,94 "
        "TOTAL A PAGAR 36.041,36"
    )

    items, _ = _detect_card_movements(text, "2026-08")

    assert [item.description for item in items] == [
        "MERPAGO*MELI 06/26",
        "PERSFLOW25810002 07/26",
        "MERPAGO*LATARIMA",
    ]
    assert [item.installments for item in items] == [None, None, "5/6"]
