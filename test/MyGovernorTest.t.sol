// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {MyGovernor} from "src/MyGovernor.sol";
import {GovToken} from "src/GovToken.sol";
import {Timelock} from "src/Timelock.sol";
import {Box} from "src/Box.sol";    

contract MyGovernorTest is Test {

    MyGovernor public governor;
    GovToken public govToken;
    Timelock public timelock;
    Box public box;

    address public USER = makeAddr("user");
    uint256 public constant INIT_SUPPLY = 100 ether;
    uint256 public constant MIN_DELAY = 3600;
    uint256 public constant VOTING_PERIOD = 50400;

    uint256 public constant VOTING_DELAY = 1;

    address[] public proposers;
    address[] public executors;

    uint256[] public values;
    bytes[] public calldatas;
    address[] public targets;


    function setUp() public {
        govToken = new GovToken();
        govToken.mint(USER, INIT_SUPPLY);

        vm.startPrank(USER);
        govToken.delegate(USER);
        timelock = new Timelock(MIN_DELAY, proposers, executors);

        governor = new MyGovernor(govToken, timelock);

        bytes32 proposerRole = timelock.PROPOSER_ROLE();
        bytes32 executorRole = timelock.EXECUTOR_ROLE();
        bytes32 adminRole = timelock.TIMELOCK_ADMIN_ROLE();

        timelock.grantRole(proposerRole, address(governor));
        timelock.grantRole(executorRole, address(0));
        timelock.revokeRole(adminRole, USER);

        vm.stopPrank();

        box = new Box();
        box.transferOwnership(address(timelock));
        
    }

    function testCantUpdateBoxWithoutGovernance() public {
        vm.expectRevert();
        box.store(7);

    }

    function testGovernanceUpdatesBox() public {
        uint256 valuetostore = 333;
        string memory description = "Store in Box";
        bytes memory encodedFunctionCall = abi.encodeWithSignature("store(uint256)", valuetostore);
        
        calldatas.push(encodedFunctionCall);
        values.push(0);
        targets.push(address(box));

        //1. Proposal
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        // View the State
        console.log("Proposal State 1: ", uint256(governor.state(proposalId)));

        vm.warp(block.timestamp + VOTING_DELAY + 1);
        vm.roll(block.number + VOTING_DELAY + 1);
        console.log("Proposal State 2: ", uint256(governor.state(proposalId)));

        //2. Vote
        string memory reason = "Cool number";

        vm.prank(USER);
        governor.castVoteWithReason(proposalId, 1, reason);

        vm.warp(block.timestamp + VOTING_PERIOD + 1);
        vm.roll(block.number + VOTING_PERIOD + 1);

        // 3. Queue the Proposal
        bytes32 descriptionHash = keccak256(abi.encodePacked(description));
        governor.queue(targets, values, calldatas, descriptionHash);

        vm.warp(block.timestamp + MIN_DELAY + 1);
        vm.roll(block.number + MIN_DELAY + 1);

        // 4. Execute the Proposal
        governor.execute(targets, values, calldatas, descriptionHash);

        console.log("Box Value: ", box.getNumber());
        assert(box.getNumber() == valuetostore);


        

    }

}