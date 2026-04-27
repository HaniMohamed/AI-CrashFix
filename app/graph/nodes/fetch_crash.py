def fetch_crash(state):
    state["crash_id"] = "test"
    state["exception"] = "test"
    state["stacktrace"] = [
        "#0   PaymentService.process (package:super_app/apps/individuals/benefits/controller/benefit_state_controller.dart:82:15)",
        "#1   CheckoutBloc._submit (package:my_app/bloc/checkout_bloc.dart:120:10)",
        "at com.example.app.PaymentActivity.process(PaymentActivity.kt:85)",
    ]
    return state