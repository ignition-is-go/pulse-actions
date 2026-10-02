pub fn contract_probe() -> bool {
    true
}

#[cfg(test)]
mod tests {
    #[test]
    fn prepared_job_runs_cargo() {
        assert!(super::contract_probe());
    }
}
