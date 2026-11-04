import os


def get_version() -> str:
    return os.environ.get("APP_VERSION", "0.1.0-dev")


def main() -> None:
    print(f"App version: {get_version()}")


if __name__ == "__main__":
    main()
