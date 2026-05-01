// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * ProFile — Esports Player Career Registry
 *
 * Paste this into Remix IDE (https://remix.ethereum.org)
 * Use the JavaScript VM environment — no wallet needed.
 *
 * QUICK START:
 *   1. Deploy → you become the owner
 *   2. addOrg() with a name + an address from the Remix account list
 *   3. Switch to that org address in the Account dropdown
 *   4. registerPlayer(), submitRecord(), issueBan()
 *   5. getPlayer() / getRecord() to read data back
 */

contract ProFile {

    // ─────────────────────────────────────────────
    // TYPES
    // ─────────────────────────────────────────────

    enum RecordType { Tournament, Transfer, Stats, Contract }

    struct Org {
        string  name;
        bool    exists;
        bool    canBan;
        uint256 submissionCount;
    }

    struct Player {
        string  handle;
        string  realName;
        string  game;
        string  team;
        address wallet;
        bool    exists;
    }

    struct Record {
        uint256    id;
        bytes32    playerId;
        address    submittedBy;
        RecordType recordType;
        string     data;         // JSON string e.g. '{"event":"IEM 2025","placement":"1st"}'
        uint256    timestamp;
    }

    struct Ban {
        bytes32  playerId;
        address  issuedBy;
        string   reason;
        uint256  issuedAt;
        bool     permanent;
        bool     active;
    }

    // ─────────────────────────────────────────────
    // STATE
    // ─────────────────────────────────────────────

    address public owner;

    mapping(address => Org)      public orgs;
    mapping(bytes32 => Player)   public players;
    mapping(bytes32 => Record[]) public playerRecords;
    mapping(bytes32 => Ban)      public activeBans;

    bytes32[] public playerIds;
    uint256 private _recordCounter;

    // ─────────────────────────────────────────────
    // EVENTS
    // ─────────────────────────────────────────────

    event OrgAdded         (address indexed orgAddress, string name, bool canBan);
    event PlayerRegistered (bytes32 indexed playerId, string handle, string game);
    event RecordSubmitted  (bytes32 indexed playerId, uint256 recordId, RecordType recordType, address org);
    event BanIssued        (bytes32 indexed playerId, address issuedBy, string reason, bool permanent);
    event BanLifted        (bytes32 indexed playerId, address liftedBy);

    // ─────────────────────────────────────────────
    // MODIFIERS
    // ─────────────────────────────────────────────

    modifier onlyOwner() {
        require(msg.sender == owner, "Not the contract owner");
        _;
    }

    modifier onlyOrg() {
        require(orgs[msg.sender].exists, "Caller is not a registered org");
        _;
    }

    modifier onlyBanOrg() {
        require(orgs[msg.sender].exists, "Caller is not a registered org");
        require(orgs[msg.sender].canBan, "Org does not have ban authority");
        _;
    }

    modifier playerExists(bytes32 playerId) {
        require(players[playerId].exists, "Player not found");
        _;
    }

    // ─────────────────────────────────────────────
    // CONSTRUCTOR
    // ─────────────────────────────────────────────

    constructor() {
        owner = msg.sender;
    }

    // ─────────────────────────────────────────────
    // OWNER — ORG MANAGEMENT
    // ─────────────────────────────────────────────

    /**
     * @notice Add a verified organisation as a trusted node.
     * @param orgAddress Wallet this org signs from (copy from Remix Account dropdown).
     * @param name       Display name e.g. "ESL Gaming"
     * @param canBan     Whether this org can issue cross-network bans.
     */
    function addOrg(address orgAddress, string calldata name, bool canBan)
        external onlyOwner
    {
        require(!orgs[orgAddress].exists, "Org already registered");
        orgs[orgAddress] = Org({
            name: name, exists: true, canBan: canBan, submissionCount: 0
        });
        emit OrgAdded(orgAddress, name, canBan);
    }

    /**
     * @notice Revoke an org's write access.
     */
    function revokeOrg(address orgAddress) external onlyOwner {
        require(orgs[orgAddress].exists, "Org not found");
        orgs[orgAddress].exists = false;
    }

    // ─────────────────────────────────────────────
    // ORG — PLAYER REGISTRATION
    // ─────────────────────────────────────────────

    /**
     * @notice Register a new player. Any verified org can call this.
     * @param handle   Competitive alias e.g. "zywOo"
     * @param realName Full legal name e.g. "Mathieu Herbaut"
     * @param game     Game title e.g. "CS2"
     * @param team     Current team e.g. "Team Vitality"
     * @param wallet   Player's wallet address (their on-chain identity)
     * @return playerId bytes32 ID — save this, you need it for all other calls
     */
    function registerPlayer(
        string  calldata handle,
        string  calldata realName,
        string  calldata game,
        string  calldata team,
        address          wallet
    ) external onlyOrg returns (bytes32 playerId) {
        playerId = keccak256(abi.encodePacked(handle, game));
        require(!players[playerId].exists, "Player already registered");

        players[playerId] = Player({
            handle: handle, realName: realName, game: game,
            team: team, wallet: wallet, exists: true
        });

        playerIds.push(playerId);
        emit PlayerRegistered(playerId, handle, game);
    }

    // ─────────────────────────────────────────────
    // ORG — SUBMIT RECORD
    // ─────────────────────────────────────────────

    /**
     * @notice Submit a verified career record. Blocked if player is banned.
     * @param playerId   The bytes32 ID from registerPlayer() or getPlayerId()
     * @param recordType 0=Tournament  1=Transfer  2=Stats  3=Contract
     * @param data       JSON string with the payload
     *
     * Example data strings:
     *   Tournament : '{"event":"IEM Katowice 2025","placement":"1st","prize":"$125000"}'
     *   Transfer   : '{"from":"Team Liquid","to":"Team Vitality","date":"2025-01-10"}'
     *   Stats      : '{"season":"Q1 2025","rating":"1.31","kd":"1.28"}'
     *   Contract   : '{"detail":"Extension signed","start":"2025-01-01","end":"2026-12-31"}'
     */
    function submitRecord(
        bytes32    playerId,
        RecordType recordType,
        string calldata data
    ) external onlyOrg playerExists(playerId) {
        require(!activeBans[playerId].active, "Player is banned — submission blocked");

        _recordCounter++;
        playerRecords[playerId].push(Record({
            id: _recordCounter,
            playerId: playerId,
            submittedBy: msg.sender,
            recordType: recordType,
            data: data,
            timestamp: block.timestamp
        }));

        orgs[msg.sender].submissionCount++;
        emit RecordSubmitted(playerId, _recordCounter, recordType, msg.sender);
    }

    // ─────────────────────────────────────────────
    // BAN SYSTEM
    // ─────────────────────────────────────────────

    /**
     * @notice Issue a ban that propagates across the entire network.
     *         Only orgs with canBan=true can call this.
     * @param playerId  The bytes32 player ID
     * @param reason    Rule violation e.g. "Match-fixing — Rulebook 4.1(a)"
     * @param permanent True = indefinite, false = 365-day ban
     */
    function issueBan(
        bytes32 playerId,
        string calldata reason,
        bool permanent
    ) external onlyBanOrg playerExists(playerId) {
        require(!activeBans[playerId].active, "Player already has an active ban");

        activeBans[playerId] = Ban({
            playerId: playerId,
            issuedBy: msg.sender,
            reason: reason,
            issuedAt: block.timestamp,
            permanent: permanent,
            active: true
        });

        emit BanIssued(playerId, msg.sender, reason, permanent);
    }

    /**
     * @notice Lift a ban. Only the issuing org or the contract owner can do this.
     */
    function liftBan(bytes32 playerId) external playerExists(playerId) {
        Ban storage b = activeBans[playerId];
        require(b.active, "No active ban for this player");
        require(
            msg.sender == owner || msg.sender == b.issuedBy,
            "Only the issuing org or owner can lift this ban"
        );
        b.active = false;
        emit BanLifted(playerId, msg.sender);
    }

    // ─────────────────────────────────────────────
    // READ FUNCTIONS
    // ─────────────────────────────────────────────

    /**
     * @notice Get a player's full profile + ban status.
     */
    function getPlayer(bytes32 playerId) external view
        returns (
            string  memory handle,
            string  memory realName,
            string  memory game,
            string  memory team,
            address        wallet,
            bool           isBanned,
            string  memory banReason,
            uint256        recordCount
        )
    {
        Player storage p = players[playerId];
        require(p.exists, "Player not found");
        Ban storage b = activeBans[playerId];
        return (
            p.handle, p.realName, p.game, p.team, p.wallet,
            b.active, b.reason,
            playerRecords[playerId].length
        );
    }

    /**
     * @notice Get a specific record by index.
     *         Use getPlayer() to find recordCount, then iterate 0 to recordCount-1.
     */
    function getRecord(bytes32 playerId, uint256 index) external view
        returns (
            uint256    id,
            address    submittedBy,
            string     memory orgName,
            RecordType recordType,
            string     memory data,
            uint256    timestamp
        )
    {
        Record storage r = playerRecords[playerId][index];
        return (
            r.id, r.submittedBy, orgs[r.submittedBy].name,
            r.recordType, r.data, r.timestamp
        );
    }

    /**
     * @notice Total number of registered players.
     */
    function getPlayerCount() external view returns (uint256) {
        return playerIds.length;
    }

    /**
     * @notice Get the bytes32 playerId for a handle + game combo.
     *         Call this any time you need to look up an ID without registering.
     */
    function getPlayerId(string calldata handle, string calldata game)
        external pure returns (bytes32)
    {
        return keccak256(abi.encodePacked(handle, game));
    }

    /**
     * @notice Get org info by address.
     */
    function getOrg(address orgAddress) external view
        returns (string memory name, bool exists, bool canBan, uint256 submissionCount)
    {
        Org storage o = orgs[orgAddress];
        return (o.name, o.exists, o.canBan, o.submissionCount);
    }
}
