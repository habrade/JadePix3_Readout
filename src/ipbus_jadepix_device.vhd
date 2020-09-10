----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 08/16/2020 08:48:44 PM
-- Design Name: 
-- Module Name: ipbus_jadepix_device - behv
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
-- 
----------------------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.all;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

use work.ipbus.all;
use work.ipbus_reg_types.all;

use work.jadepix_defines.all;

entity ipbus_jadepix_device is
  port(
    ipb_clk : in  std_logic;
    ipb_rst : in  std_logic;
    ipb_in  : in  ipb_wbus;
    ipb_out : out ipb_rbus;

    clk : in std_logic;
    rst : in std_logic;

    -- chip config fifo
    cfg_start      : out std_logic;
    cfg_sync       : out jadepix_cfg;
    cfg_fifo_rst   : out std_logic;
    cfg_busy       : in  std_logic;
    cfg_fifo_empty : in  std_logic;
    cfg_fifo_pfull : in  std_logic;
    cfg_fifo_count : in  std_logic_vector(CFG_FIFO_COUNT_WITDH-1 downto 0);

    CACHE_BIT_SET : out std_logic_vector(3 downto 0);

    hitmap_col_low  : out std_logic_vector(COL_WIDTH-1 downto 0);
    hitmap_col_high : out std_logic_vector(COL_WIDTH-1 downto 0);
    hitmap_en       : out std_logic;
    hitmap_num      : out std_logic_vector(3 downto 0);


    rs_busy         : in  std_logic;
    rs_start        : out std_logic;
    rs_frame_number : out std_logic_vector(31 downto 0);

    gs_start      : out std_logic;
    gshutter_soft : out std_logic;
    aplse_soft    : out std_logic;
    dplse_soft    : out std_logic;
    gs_col        : out std_logic_vector(COL_WIDTH-1 downto 0);

    gs_sel_pulse            : out std_logic;
    gs_busy                 : in  std_logic;
    gs_pulse_delay_cnt      : out std_logic_vector(8 downto 0);
    gs_pulse_width_cnt_low  : out std_logic_vector(31 downto 0);
    gs_pulse_width_cnt_high : out std_logic_vector(1 downto 0);
    gs_pulse_deassert_cnt   : out std_logic_vector(8 downto 0);
    gs_deassert_cnt         : out std_logic_vector(8 downto 0);


    anasel_en_soft : out std_logic;
    digsel_en_soft : out std_logic;

    PDB  : out std_logic;
    LOAD : out std_logic
    );
end ipbus_jadepix_device;

architecture behv of ipbus_jadepix_device is
  -- IPbus reg
  constant SYNC_REG_ENA               : boolean := false;
  constant N_STAT                     : integer := 2;
  constant N_CTRL                     : integer := 9;
  constant N_RAM                      : integer := 0;
  signal stat                         : ipb_reg_v(N_STAT-1 downto 0);
  signal ctrl                         : ipb_reg_v(N_CTRL-1 downto 0);
  signal ctrl_reg_stb, ctrl_reg_stb_r : std_logic_vector(N_CTRL-1 downto 0);
  signal stat_reg_stb, stat_reg_stb_r : std_logic_vector(N_STAT-1 downto 0);

  signal cfg_start_tmp     : std_logic;
  signal rs_start_tmp      : std_logic;
  signal gs_start_tmp      : std_logic;
  signal cache_bit_set_tmp : std_logic_vector(3 downto 0);
  signal hitmap_en_tmp     : std_logic;
  signal load_tmp          : std_logic;

  -- IPbus drp
--  signal ram_rst : std_logic_vector(N_RAM-1 downto 0);

  signal cfg : jadepix_cfg;

  -- DEBUG
  attribute mark_debug                    : string;
  attribute mark_debug of LOAD            : signal is "true";
  attribute mark_debug of CACHE_BIT_SET   : signal is "true";
  attribute mark_debug of PDB             : signal is "true";
  attribute mark_debug of hitmap_col_low  : signal is "true";
  attribute mark_debug of hitmap_col_high : signal is "true";
  attribute mark_debug of hitmap_en       : signal is "true";

begin

  inst_ipbus_slave_reg_ram : entity work.ipbus_slave_reg_ram
    generic map(
      SYNC_REG_ENA => SYNC_REG_ENA,
      N_STAT       => N_STAT,
      N_CTRL       => N_CTRL,
      N_RAM        => N_RAM
      )
    port map(

      ipb_clk => ipb_clk,
      ipb_rst => ipb_rst,
      ipb_in  => ipb_in,
      ipb_out => ipb_out,

      clk => clk,
      rst => rst,

      -- control/state registers
      ctrl         => ctrl,
      ctrl_reg_stb => ctrl_reg_stb,
      stat         => stat,
      stat_reg_stb => open
      );

  -- control
  process(clk)
  begin
    if rising_edge(clk) then
      cfg.wr_en <= ctrl(0)(3);
      cfg.din   <= ctrl(0)(2 downto 0);

      cfg_start_tmp  <= ctrl(1)(0);
      rs_start_tmp   <= ctrl(1)(1);
      gs_start       <= ctrl(1)(2);
      PDB            <= ctrl(1)(5);
      load_tmp       <= ctrl(1)(6);
      cfg_fifo_rst   <= ctrl(1)(7);
      cache_bit_set  <= ctrl(1)(11 downto 8);
      gs_col         <= ctrl(1)(21 downto 13);
      anasel_en_soft <= ctrl(1)(22);
      digsel_en_soft <= ctrl(1)(23);
      gs_sel_pulse   <= ctrl(1)(24);
      aplse_soft     <= ctrl(1)(25);
      dplse_soft     <= ctrl(1)(26);
      gshutter_soft  <= ctrl(1)(27);

      rs_frame_number <= ctrl(2);

      hitmap_col_low  <= ctrl(3)(8 downto 0);
      hitmap_col_high <= ctrl(3)(17 downto 9);
      hitmap_en       <= ctrl(3)(18);
      hitmap_num      <= ctrl(3)(22 downto 19);

      gs_pulse_delay_cnt      <= ctrl(4)(8 downto 0);
      gs_pulse_width_cnt_low  <= ctrl(5);
      gs_pulse_width_cnt_high <= ctrl(6)(1 downto 0);
      gs_pulse_deassert_cnt   <= ctrl(7)(8 downto 0);
      gs_deassert_cnt         <= ctrl(8)(8 downto 0);


      ctrl_reg_stb_r <= ctrl_reg_stb;
      stat_reg_stb_r <= stat_reg_stb;
    end if;
  end process;

  sync_ctrl_signals : process(clk)
  begin
    if rising_edge(clk) then
      if ctrl_reg_stb_r(0) = '1' then
        cfg_sync <= cfg;
      else
        cfg_sync <= JADEPIX_CFG_NULL;
      end if;

      if ctrl_reg_stb_r(1) = '1' then
        cfg_start <= cfg_start_tmp;
        rs_start  <= rs_start_tmp;
        LOAD      <= load_tmp;
      else
        cfg_start <= '0';
        rs_start  <= '0';
        LOAD      <= '0';
      end if;
    end if;
  end process;

  -- status
  process(clk)
  begin
    if rising_edge(clk) then
      stat(0)(0) <= cfg_busy;
      stat(0)(1) <= rs_busy;
      stat(0)(2) <= gs_busy;

      stat(1)(0)           <= cfg_fifo_empty;
      stat(1)(1)           <= cfg_fifo_pfull;
      stat(1)(18 downto 2) <= cfg_fifo_count;

    end if;
  end process;


end behv;
