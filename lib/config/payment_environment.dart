const paymentDemo = bool.fromEnvironment('PAYMENT_DEMO', defaultValue: false);
const paymentEmulatorHost =
    String.fromEnvironment('PAYMENT_EMULATOR_HOST', defaultValue: '127.0.0.1');
