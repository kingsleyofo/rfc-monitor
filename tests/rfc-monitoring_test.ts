import { Clarinet, Tx, Chain, Account, types } from 'https://deno.land/x/clarinet@v1.0.0/index.ts';
import { assertEquals } from 'https://deno.land/std@0.90.0/testing/asserts.ts';

Clarinet.test({
  name: "RFC Monitoring: Should create a new proposal",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;
    const block = chain.mineBlock([
      Tx.contractCall(
        'rfc-monitoring', 
        'create-proposal', 
        [
          types.ascii('Stacks 2.1 Upgrade Proposal'),
          types.utf8('A comprehensive proposal for Stacks 2.1 network upgrade'),
          types.uint(2_000_000)
        ],
        deployer.address
      )
    ]);

    assertEquals(block.receipts.length, 1);
    assertEquals(block.height, 2);
    block.receipts[0].result.expectOk().expectUint(1);
  }
});

Clarinet.test({
  name: "RFC Monitoring: Should submit a review for a proposal",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;
    const reviewer = accounts.get('wallet_1')!;

    // First create a proposal
    chain.mineBlock([
      Tx.contractCall(
        'rfc-monitoring', 
        'create-proposal', 
        [
          types.ascii('Stacks 2.1 Upgrade Proposal'),
          types.utf8('A comprehensive proposal for Stacks 2.1 network upgrade'),
          types.uint(2_000_000)
        ],
        deployer.address
      )
    ]);

    // Then submit a review
    const block = chain.mineBlock([
      Tx.contractCall(
        'rfc-monitoring', 
        'submit-review', 
        [
          types.uint(1),
          types.utf8('Detailed review of the Stacks 2.1 upgrade proposal'),
          types.uint(8)
        ],
        reviewer.address
      )
    ]);

    assertEquals(block.receipts.length, 1);
    block.receipts[0].result.expectOk().expectUint(1);
  }
});

Clarinet.test({
  name: "RFC Monitoring: Should complete a review and release bounty",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;
    const reviewer = accounts.get('wallet_1')!;

    // Create proposal
    chain.mineBlock([
      Tx.contractCall(
        'rfc-monitoring', 
        'create-proposal', 
        [
          types.ascii('Stacks 2.1 Upgrade Proposal'),
          types.utf8('A comprehensive proposal for Stacks 2.1 network upgrade'),
          types.uint(2_000_000)
        ],
        deployer.address
      )
    ]);

    // Submit review
    chain.mineBlock([
      Tx.contractCall(
        'rfc-monitoring', 
        'submit-review', 
        [
          types.uint(1),
          types.utf8('Detailed review of the Stacks 2.1 upgrade proposal'),
          types.uint(8)
        ],
        reviewer.address
      )
    ]);

    // Complete review
    const block = chain.mineBlock([
      Tx.contractCall(
        'rfc-monitoring', 
        'complete-review', 
        [types.uint(1)],
        deployer.address
      )
    ]);

    assertEquals(block.receipts.length, 1);
    block.receipts[0].result.expectOk();
  }
});