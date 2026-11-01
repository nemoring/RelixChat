package dev.kiwifuzzy.kiwion;

public class ApiException extends Exception {
    public final int status;
    public final String code;

    public ApiException(int status, String code, String message) {
        super(message);
        this.status = status;
        this.code = code;
    }

    public boolean isNetwork() { return status == 0; }
}
