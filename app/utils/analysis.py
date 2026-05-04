
def detect_risk_signals(code: str):
    risks = []

    if "!" in code and "null" not in code.lower():
        risks.append("possible_null_assertion")

    if "async" in code and "await" not in code:
        risks.append("async_misuse")

    if "setState" in code:
        risks.append("flutter_state_change")

    if "try" not in code and "catch" not in code:
        risks.append("no_exception_handling")

    return risks