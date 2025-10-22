Container Lifecycle Integration Tests
**Description**: End-to-end container operations with real Docker

**Acceptance Criteria**:
- [ ] Test complete provision → start → exec → stop → clean cycle
- [ ] Test multiple Ruby version isolation
- [ ] Test state persistence across operations
- [ ] Test Docker Compose file generation
- [ ] Test volume persistence and cleanup
- [ ] Require running Docker daemon
- [ ] Write good enough RSpec test and test it in terminal and make sure all pass

**Implementation Notes**:
- Mark tests as `:integration` for optional running
- Clean up Docker resources after each test
- Use unique container names to avoid conflicts

---

Auto-Provisioning Integration Tests
**Description**: Test auto-provisioning workflows

**Acceptance Criteria**:
- [x] Test first-time user flow (auto-provision with prompt)
- [x] Test stopped container auto-restart
- [x] Test version switching with resource management
- [x] Test CI/CD mode (no prompts)
- [x] Test configuration-driven behavior
- [x] Test idempotency (multiple ensure_ready calls)
- [x] Write good enough RSpec test and test it in terminal and make sure all pass

**Implementation Notes**:
- Mock user input for prompt testing
- Test with different configuration values
- Verify no prompts in CI environment
- Created spec/integration/auto_provisioning_integration_spec.rb with 9 test scenarios

---

Error Recovery Integration Tests
**Description**: Test error scenarios with real Docker

**Acceptance Criteria**:
- [ ] Test container crash recovery
- [ ] Test Docker daemon unavailable scenarios
- [ ] Test corrupted state file recovery
- [ ] Test resource cleanup after failures
- [ ] Test recovery messaging and guidance

**Implementation Notes**:
- Simulate container crashes (kill container mid-operation)
- Test recovery from various failure states
- Verify proper cleanup of partial operations

---

Update README.md
**Description**: Update project README with persistent container documentation

**Acceptance Criteria**:
- [ ] Add persistent container mode overview
- [ ] Document all new CLI commands with examples
- [ ] Add configuration reference
- [ ] Include performance comparison
- [ ] Add troubleshooting section
- [ ] Update installation and setup instructions

**Implementation Notes**:
- Include migration guide from ephemeral mode
- Add FAQ section for common issues
- Include performance benchmarks
