use clap::Parser;
use luxel_cli::{Cli, run};

fn main() {
    let cli = Cli::parse_from(luxel_cli::normalize_aliases(std::env::args_os()));
    if let Err(error) = run(cli) {
        eprintln!("luxel: {error}");
        std::process::exit(error.exit_code());
    }
}
