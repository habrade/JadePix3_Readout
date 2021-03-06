library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

library UNISIM;
use UNISIM.vcomponents.all;

use work.ipbus.all;
use work.drp_decl.all;

use work.global_defines.all;
use work.jadepix_defines.all;


entity JadePix3_Readout is port(
  sysclk_p     : in  std_logic;
  sysclk_n     : in  std_logic;
  leds         : out std_logic_vector(3 downto 0);  -- status LEDs
  dip_sw       : in  std_logic_vector(3 downto 0);  -- switches
  gmii_gtx_clk : out std_logic;
  gmii_tx_en   : out std_logic;
  gmii_tx_er   : out std_logic;
  gmii_txd     : out std_logic_vector(7 downto 0);
  gmii_rx_clk  : in  std_logic;
  gmii_rx_dv   : in  std_logic;
  gmii_rx_er   : in  std_logic;
  gmii_rxd     : in  std_logic_vector(7 downto 0);
  phy_rst      : out std_logic;

  --  In-chip fifo
  VALID_IN     : in  std_logic_vector(3 downto 0);
  FIFO_READ_EN : out std_logic;
  BLK_SELECT   : out std_logic_vector(BLK_SELECT_WIDTH-1 downto 0);
  INQUIRY      : out std_logic_vector(1 downto 0);
  DATA_IN      : in  std_logic_vector(7 downto 0);


--  MATRIX_DIN : in std_logic_vector(15 downto 0);

--  -- SDRAM
--  ddr3_dq    : inout std_logic_vector(63 downto 0);
--  ddr3_dqs_p : inout std_logic_vector(7 downto 0);
--  ddr3_dqs_n : inout std_logic_vector(7 downto 0);

--  ddr3_addr    : out std_logic_vector(13 downto 0);
--  ddr3_ba      : out std_logic_vector(2 downto 0);
--  ddr3_ras_n   : out std_logic;
--  ddr3_cas_n   : out std_logic;
--  ddr3_we_n    : out std_logic;
--  ddr3_reset_n : out std_logic;
--  ddr3_ck_p    : out std_logic_vector(0 downto 0);
--  ddr3_ck_n    : out std_logic_vector(0 downto 0);
--  ddr3_cke     : out std_logic_vector(0 downto 0);
--  ddr3_cs_n    : out std_logic_vector(0 downto 0);
--  ddr3_dm      : out std_logic_vector(7 downto 0);
--  ddr3_odt     : out std_logic_vector(0 downto 0);

  -- DAC70004
  DAC_SCLK : out std_logic;
  DAC_LDAC : out std_logic;
  DAC_SYNC : out std_logic;
  DAC_SDIN : out std_logic;
  DAC_CLR  : out std_logic;
--  DAC_BUSY : out std_logic

  -- JadePix3
  REFCLK    : in  std_logic;
  CACHE_CLK : out std_logic;
  RX_FPGA   : out std_logic;

  HITMAP_IN : in std_logic_vector(15 downto 0);

--  LVDS_RX_IN_P : in std_logic;
--  LVDS_RX_IN_N : in std_logic;

  RA    : out std_logic_vector(ROW_WIDTH-1 downto 0);
  RA_EN : out std_logic;
  CA    : out std_logic_vector(COL_WIDTH-1 downto 0);
  CA_EN : out std_logic;

  CON_SELM : out std_logic;
  CON_SELP : out std_logic;
  CON_DATA : out std_logic;

  CACHE_BIT_SET : out std_logic_vector(3 downto 0);
  HIT_RST       : out std_logic;
  RD_EN         : out std_logic;

  MATRIX_GRST : out std_logic;
  DIGSEL_EN   : out std_logic;
  ANASEL_EN   : out std_logic;
  GSHUTTER    : out std_logic;
  DPLSE       : out std_logic;
  APLSE       : out std_logic;

--  PDB            : out std_logic;
  LOAD           : out std_logic;
  POR            : out std_logic;       -- dac70004 power-on-reset
  SN_OEn         : out std_logic;  -- enabel clock level shift output, low active
  EN_diff        : out std_logic;
  Ref_clk_1G_f   : out std_logic;
  CLK_SEL        : out std_logic;
  D_RST          : out std_logic;
  SERIALIZER_RST : out std_logic;

  -- SPI Master
  ss   : out std_logic_vector(N_SS - 1 downto 0);
  mosi : out std_logic;
  miso : in  std_logic;
  sclk : out std_logic
  );
end JadePix3_Readout;

architecture rtl of JadePix3_Readout is

  signal sysclk                                               : std_logic;
  signal clk_sys                                              : std_logic;
  signal clk_fpga                                             : std_logic;
  signal clk_wfifo                                            : std_logic;
  signal clk_ref_rst, clk_dac_rst, clk_sys_rst, clk_wfifo_rst : std_logic;


  -- IPbus
  signal clk_ipb, rst_ipb, clk_125M, clk_aux, rst_aux, locked_ipbus_mmcm, nuke, soft_rst, phy_rst_e, userled : std_logic;
  signal mac_addr                                                                                            : std_logic_vector(47 downto 0);
  signal ip_addr                                                                                             : std_logic_vector(31 downto 0);
  signal ipb_out                                                                                             : ipb_wbus;
  signal ipb_in                                                                                              : ipb_rbus;

  -- DAC70004
  signal DACCLK   : std_logic;
  signal DAC_BUSY : std_logic;
  signal DAC_WE   : std_logic;
  signal DAC_DATA : std_logic_vector(31 downto 0);

  attribute mark_debug             : string;
  attribute mark_debug of DAC_BUSY : signal is "true";
  attribute mark_debug of DAC_WE   : signal is "true";
  attribute mark_debug of DAC_DATA : signal is "true";
  attribute mark_debug of ipb_out  : signal is "true";
  attribute mark_debug of ipb_in   : signal is "true";

  -- JadePix
  signal locked_jadepix_mmcm : std_logic;
  signal cfg_busy            : std_logic;
  signal rs_busy             : std_logic;
  signal cfg_start           : std_logic;
  signal rs_start            : std_logic;
  signal gs_start            : std_logic;
  signal rs_frame_start      : std_logic;
  signal rs_frame_num_set    : std_logic_vector(FRAME_CNT_WIDTH-1 downto 0);
  signal rs_frame_cnt        : std_logic_vector(FRAME_CNT_WIDTH-1 downto 0);


  signal hitmap_col_low  : std_logic_vector(COL_WIDTH-1 downto 0);
  signal hitmap_col_high : std_logic_vector(COL_WIDTH-1 downto 0);
  signal hitmap_en       : std_logic;
  signal hitmap_num      : std_logic_vector(HITMAP_NUM_WIDTH-1 downto 0);

  signal gs_sel_pulse : std_logic;

  signal gs_col  : std_logic_vector(COL_WIDTH-1 downto 0);
  signal gs_busy : std_logic;

  signal gs_pulse_delay_cnt      : std_logic_vector(8 downto 0);
  signal gs_pulse_width_cnt_low  : std_logic_vector(31 downto 0);
  signal gs_pulse_width_cnt_high : std_logic_vector(1 downto 0);
  signal gs_pulse_deassert_cnt   : std_logic_vector(8 downto 0);
  signal gs_deassert_cnt         : std_logic_vector(8 downto 0);

  signal start_cache   : std_logic;
  signal clk_cache     : std_logic;
  signal is_busy_cache : std_logic;

  -- Config FIFO signals
--  signal cfg_fifo_empty : std_logic;
--  signal cfg_fifo_pfull : std_logic;
--  signal cfg_fifo_count : std_logic_vector(CFG_FIFO_COUNT_WITDH-1 downto 0);

  signal anasel_en_gs : std_logic;
  signal digsel_en_rs : std_logic;
  signal aplse_gs     : std_logic;
  signal dplse_gs     : std_logic;
  signal gshutter_gs  : std_logic;

  signal digsel_en_soft : std_logic;
  signal anasel_en_soft : std_logic;
  signal aplse_soft     : std_logic;
  signal dplse_soft     : std_logic;
  signal gshutter_soft  : std_logic;

  signal digsel_en_manually : std_logic;
  signal anasel_en_manually : std_logic;
  signal aplse_manually     : std_logic;
  signal dplse_manually     : std_logic;
  signal gshutter_manually  : std_logic;

  -- FIFOs
  signal data_fifo_rst                : std_logic;
  signal slow_ctrl_fifo_rd_en         : std_logic;
  signal slow_ctrl_fifo_valid         : std_logic;
  signal slow_ctrl_fifo_empty         : std_logic;
  signal slow_ctrl_fifo_prog_full     : std_logic;
  signal slow_ctrl_fifo_wr_data_count : std_logic_vector(CFG_FIFO_COUNT_WITDH-1 downto 0);
  signal slow_ctrl_fifo_rd_dout       : std_logic_vector(31 downto 0);

  signal data_fifo_wr_clk      : std_logic;
  signal data_fifo_wr_en       : std_logic;
  signal data_fifo_wr_din      : std_logic_vector(31 downto 0);
  signal data_fifo_full        : std_logic;
  signal data_fifo_almost_full : std_logic;

  -- Readout
  signal clk_cache_delay : std_logic;
  signal row_num         : std_logic_vector(ROW_WIDTH-1 downto 0);
  signal rd_data_rst     : std_logic;

  -- SPI 
  signal load_soft     : std_logic;
  signal spi_trans_end : std_logic;

  -- DEBUG
  signal debug                : std_logic;
  signal ca_en_soft           : std_logic;
  signal ca_en_manually       : std_logic;
  signal ca_en_logic          : std_logic;
  signal ca_soft              : std_logic_vector(COL_WIDTH-1 downto 0);
  signal ca_soft_manually     : std_logic;
  signal ca_logic             : std_logic_vector(COL_WIDTH-1 downto 0);
  signal matrix_grst_soft     : std_logic;
  signal matrix_grst_manually : std_logic;
  signal matrix_grst_logic    : std_logic;
  signal hit_rst_soft         : std_logic;
  signal hit_rst_manually     : std_logic;
  signal hit_rst_logic        : std_logic;

  -- for test
  signal hitmap_r          : std_logic_vector(15 downto 0);
  signal sel_chip_clk      : std_logic := '0';
  signal rx_fpga_tmp1      : std_logic := '0';
  signal rx_fpga_tmp2      : std_logic := '0';
  signal rx_fpga_oe        : std_logic;
  signal cfg_add_factor_t0 : std_logic_vector(7 downto 0);
  signal cfg_add_factor_t1 : std_logic_vector(15 downto 0);
  signal cfg_add_factor_t2 : std_logic_vector(7 downto 0);

  attribute mark_debug of hitmap_r  : signal is "true";
  attribute mark_debug of DPLSE     : signal is "true";
  attribute mark_debug of APLSE     : signal is "true";
  attribute mark_debug of DIGSEL_EN : signal is "true";
  attribute mark_debug of ANASEL_EN : signal is "true";
  attribute mark_debug of GSHUTTER  : signal is "true";
  attribute mark_debug of LOAD      : signal is "true";
  attribute mark_debug of VALID_IN  : signal is "true";
  attribute mark_debug of DATA_IN   : signal is "true";

  attribute mark_debug of BLK_SELECT   : signal is "true";
  attribute mark_debug of FIFO_READ_EN : signal is "true";
  attribute mark_debug of HIT_RST      : signal is "true";

  attribute mark_debug of CA             : signal is "true";
  attribute mark_debug of CA_EN          : signal is "true";
  attribute mark_debug of ca_soft        : signal is "true";
  attribute mark_debug of hit_rst_soft   : signal is "true";
  attribute mark_debug of hit_rst_logic  : signal is "true";
  attribute mark_debug of ca_logic       : signal is "true";
  attribute mark_debug of ca_en_soft     : signal is "true";
  attribute mark_debug of ca_en_logic    : signal is "true";
  attribute mark_debug of debug          : signal is "true";
  attribute mark_debug of digsel_en_soft : signal is "true";
  attribute mark_debug of anasel_en_soft : signal is "true";
  attribute mark_debug of aplse_soft     : signal is "true";
  attribute mark_debug of dplse_soft     : signal is "true";
  attribute mark_debug of sel_chip_clk   : signal is "true";

  attribute mark_debug of slow_ctrl_fifo_rd_en         : signal is "true";
  attribute mark_debug of slow_ctrl_fifo_valid         : signal is "true";
  attribute mark_debug of slow_ctrl_fifo_empty         : signal is "true";
  attribute mark_debug of slow_ctrl_fifo_rd_dout       : signal is "true";
  attribute mark_debug of slow_ctrl_fifo_prog_full     : signal is "true";
  attribute mark_debug of slow_ctrl_fifo_wr_data_count : signal is "true";

begin

  process(clk_sys)
  begin
    if rising_edge(clk_sys) then
      hitmap_r <= HITMAP_IN;
    end if;
  end process;

  OBUFDS_CACHE_CLK : OBUF
    generic map (
      DRIVE      => 12,
      IOSTANDARD => "DEFAULT",
      SLEW       => "SLOW")
    port map (
      O => CACHE_CLK,  -- Buffer output (connect directly to top-level port)
      I => clk_cache                    -- Buffer input 
      );

  OBUF_RX_CLK : OBUF
    generic map (
      DRIVE      => 12,
      IOSTANDARD => "DEFAULT",
      SLEW       => "SLOW")
    port map (
      O => RX_FPGA,      -- Buffer output (connect directly to top-level port)
      I => rx_fpga_tmp2                 -- Buffer input 
      );

  BUFGMUX_CTRL_inst : BUFGMUX_CTRL
    port map (
      O  => rx_fpga_tmp1,               -- 1-bit output: Clock output
      I0 => clk_fpga,                   -- 1-bit input: Clock input (S=0)
      I1 => clk_sys,                    -- 1-bit input: Clock input (S=1)
      S  => sel_chip_clk                -- 1-bit input: Clock select
      );

  BUFGCE_inst : BUFGCE
    port map (
      O  => rx_fpga_tmp2,               -- 1-bit output: Clock output
      CE => rx_fpga_oe,    -- 1-bit input: Clock enable input for I0
      I  => rx_fpga_tmp1                -- 1-bit input: Primary clock
      );

  ibufgds0 : IBUFGDS port map(
    i  => sysclk_p,
    ib => sysclk_n,
    o  => sysclk
    );

  jadepix_clocks : entity work.jadepix_clock_gen
    port map(
      sysclk      => sysclk,
      clk_ref     => open,
      clk_dac     => DACCLK,
      clk_sys     => clk_sys,
      clk_fpga    => clk_fpga,
      clk_dac_rst => clk_dac_rst,
      clk_ref_rst => clk_ref_rst,
      clk_sys_rst => clk_sys_rst,
      locked      => locked_jadepix_mmcm
      );

  ipbus_infra : entity work.ipbus_gmii_infra
    generic map(
      CLK_AUX_FREQ => 50.0
      )
    port map(
      sysclk       => sysclk,
      clk_ipb_o    => clk_ipb,
      rst_ipb_o    => rst_ipb,
      clk_125_o    => clk_125M,
      rst_125_o    => phy_rst_e,
      clk_aux_o    => clk_aux,
      rst_aux_o    => rst_aux,
      locked_o     => locked_ipbus_mmcm,
      nuke         => nuke,
      soft_rst     => soft_rst,
      leds         => leds(1 downto 0),
      gmii_gtx_clk => gmii_gtx_clk,
      gmii_txd     => gmii_txd,
      gmii_tx_en   => gmii_tx_en,
      gmii_tx_er   => gmii_tx_er,
      gmii_rx_clk  => gmii_rx_clk,
      gmii_rxd     => gmii_rxd,
      gmii_rx_dv   => gmii_rx_dv,
      gmii_rx_er   => gmii_rx_er,
      mac_addr     => mac_addr,
      ip_addr      => ip_addr,
      ipb_in       => ipb_in,
      ipb_out      => ipb_out
      );

  leds(3 downto 2) <= '0' & locked_jadepix_mmcm;
  phy_rst          <= not phy_rst_e;

  mac_addr <= X"020ddba1151" & dip_sw;  -- Careful here, arbitrary addresses do not always work
  ip_addr  <= X"c0a8031" & dip_sw;      -- 192.168.3.16+n (n:0-15)

-- ipbus slaves live in the entity below, and can expose top-level ports
-- The ipbus fabric is instantiated within.

  ipbus_payload : entity work.ipbus_payload
    generic map(
      N_SS => N_SS
      )
    port map(
      ipb_clk => clk_ipb,
      ipb_rst => rst_ipb,
      ipb_in  => ipb_out,
      ipb_out => ipb_in,

      -- Chip system clock
      clk => clk_sys,
      rst => clk_sys_rst,

      -- Global
      nuke     => nuke,
      soft_rst => soft_rst,

      -- DAC70004
      DACCLK     => DACCLK,
      DACCLK_RST => clk_dac_rst,
      DAC_BUSY   => DAC_BUSY,
      DAC_WE     => DAC_WE,
      DAC_DATA   => DAC_DATA,

      -- JadePix
      cfg_start => cfg_start,
      cfg_busy  => cfg_busy,

      INQUIRY       => INQUIRY,
      CACHE_BIT_SET => CACHE_BIT_SET,

      rs_start         => rs_start,
      rs_busy          => rs_busy,
      rs_frame_num_set => rs_frame_num_set,


      hitmap_col_low  => hitmap_col_low,
      hitmap_col_high => hitmap_col_high,
      hitmap_en       => hitmap_en,
      hitmap_num      => hitmap_num,

      gs_start     => gs_start,
      gs_busy      => gs_busy,
      gs_sel_pulse => gs_sel_pulse,
      gs_col       => gs_col,

      gshutter_soft => gshutter_soft,
      aplse_soft    => aplse_soft,
      dplse_soft    => dplse_soft,

      gs_pulse_delay_cnt      => gs_pulse_delay_cnt,
      gs_pulse_width_cnt_low  => gs_pulse_width_cnt_low,
      gs_pulse_width_cnt_high => gs_pulse_width_cnt_high,
      gs_pulse_deassert_cnt   => gs_pulse_deassert_cnt,
      gs_deassert_cnt         => gs_deassert_cnt,

      anasel_en_soft => anasel_en_soft,
      digsel_en_soft => digsel_en_soft,
      load_soft      => load_soft,

      spi_trans_end => spi_trans_end,

      PDB               => open,
      SN_OEn            => SN_OEn,
      POR               => POR,
      EN_diff           => EN_diff,
      Ref_clk_1G_f      => Ref_clk_1G_f,
      CLK_SEL           => CLK_SEL,
      D_RST             => D_RST,
      SERIALIZER_RST    => SERIALIZER_RST,
      sel_chip_clk      => sel_chip_clk,
      cfg_add_factor_t0 => cfg_add_factor_t0,
      cfg_add_factor_t1 => cfg_add_factor_t1,
      cfg_add_factor_t2 => cfg_add_factor_t2,

      -- FIFOs
      slow_ctrl_fifo_rd_clk        => clk_sys,
      slow_ctrl_fifo_rd_en         => slow_ctrl_fifo_rd_en,
      slow_ctrl_fifo_valid         => slow_ctrl_fifo_valid,
      slow_ctrl_fifo_empty         => slow_ctrl_fifo_empty,
      slow_ctrl_fifo_rd_dout       => slow_ctrl_fifo_rd_dout,
      slow_ctrl_fifo_prog_full     => slow_ctrl_fifo_prog_full,
      slow_ctrl_fifo_wr_data_count => slow_ctrl_fifo_wr_data_count,
      data_fifo_rst                => data_fifo_rst,
      data_fifo_wr_clk             => data_fifo_wr_clk,
      data_fifo_wr_en              => data_fifo_wr_en,
      data_fifo_full               => data_fifo_full,
      data_fifo_almost_full        => data_fifo_almost_full,
      data_fifo_wr_din             => data_fifo_wr_din,

      -- SPI master
      ss   => open,
      mosi => mosi,
      miso => miso,
      sclk => sclk,

      -- DEBUG
      debug      => debug,
      ca_en      => ca_en_soft,
      ca_soft    => ca_soft,
      hit_rst    => hit_rst_soft,
      rx_fpga_oe => rx_fpga_oe,

      digsel_en_manually   => digsel_en_manually,
      anasel_en_manually   => anasel_en_manually,
      dplse_manually       => dplse_manually,
      aplse_manually       => aplse_manually,
      matrix_grst_manually => matrix_grst_manually,
      gshutter_manually    => gshutter_manually,
      ca_soft_manually     => ca_soft_manually,
      ca_en_manually       => ca_en_manually,
      hit_rst_manually     => hit_rst_manually

      );


  dac70004 : entity work.DAC_refresh
    port map(
      CLK_50M    => DACCLK,
      DLL_LOCKED => locked_jadepix_mmcm,
      DAC_WE     => DAC_WE,
      DAC_DATA   => DAC_DATA,
      DAC_SCLK   => DAC_SCLK,
      DAC_LOAD   => DAC_LDAC,
      DAC_SYNC   => DAC_SYNC,
      DAC_SDIN   => DAC_SDIN,
      DAC_CLR    => DAC_CLR,
      DAC_BUSY   => DAC_BUSY
      );


  jadepix_ctrl_wrapper : entity work.jadepix_ctrl_wrapper
    port map(

      clk           => clk_sys,
      rst           => clk_sys_rst,
      clk_ipb       => clk_ipb,
      rst_ipb       => rst_ipb,
      spi_trans_end => spi_trans_end,
      load_soft     => load_soft,
      LOAD          => LOAD,

      cfg_busy            => cfg_busy,
      cfg_start           => cfg_start,
      cfg_fifo_dout       => slow_ctrl_fifo_rd_dout(2 downto 0),
      cfg_fifo_dout_valid => slow_ctrl_fifo_valid,
      cfg_fifo_empty      => slow_ctrl_fifo_empty,
      cfg_fifo_pfull      => slow_ctrl_fifo_prog_full,
      cfg_fifo_count      => slow_ctrl_fifo_wr_data_count,
      cfg_fifo_rd_en      => slow_ctrl_fifo_rd_en,

      cfg_add_factor_t0 => cfg_add_factor_t0,
      cfg_add_factor_t1 => cfg_add_factor_t1,
      cfg_add_factor_t2 => cfg_add_factor_t2,

      start_cache     => start_cache,
      clk_cache       => clk_cache,
      clk_cache_delay => clk_cache_delay,
      is_busy_cache   => is_busy_cache,

      hitmap_col_low  => hitmap_col_low,
      hitmap_col_high => hitmap_col_high,
      hitmap_en       => hitmap_en,
      hitmap_num      => hitmap_num,

      RA       => row_num,
      RA_EN    => RA_EN,
      CA       => ca_logic,
      CA_EN    => ca_en_logic,
      CON_SELM => CON_SELM,
      CON_SELP => CON_SELP,
      CON_DATA => CON_DATA,

      rs_busy          => rs_busy,
      rs_start         => rs_start,
      rs_frame_num_set => rs_frame_num_set,
      rs_frame_cnt     => rs_frame_cnt,

      HIT_RST => hit_rst_logic,
      RD_EN   => RD_EN,

      MATRIX_GRST => matrix_grst_logic,

      gshutter_gs => gshutter_gs,
      aplse_gs    => aplse_gs,
      dplse_gs    => dplse_gs,

      gs_start     => gs_start,
      gs_busy      => gs_busy,
      gs_sel_pulse => gs_sel_pulse,
      gs_col       => gs_col,

      gs_pulse_delay_cnt      => gs_pulse_delay_cnt,
      gs_pulse_width_cnt_low  => gs_pulse_width_cnt_low,
      gs_pulse_width_cnt_high => gs_pulse_width_cnt_high,
      gs_pulse_deassert_cnt   => gs_pulse_deassert_cnt,
      gs_deassert_cnt         => gs_deassert_cnt,

      digsel_en_rs => digsel_en_rs,
      anasel_en_gs => anasel_en_gs
      );

  DIGSEL_EN   <= digsel_en_soft   when digsel_en_manually   else digsel_en_rs;
  ANASEL_EN   <= anasel_en_soft   when anasel_en_manually   else anasel_en_gs;
  DPLSE       <= dplse_soft       when dplse_manually       else dplse_gs;
  APLSE       <= aplse_soft       when aplse_manually       else aplse_gs;
  MATRIX_GRST <= matrix_grst_soft when matrix_grst_manually else matrix_grst_logic;
  GSHUTTER    <= gshutter_soft    when gshutter_manually    else gshutter_gs;

  RA <= row_num;

  CA      <= ca_soft      when ca_soft_manually else ca_logic;
  CA_EN   <= ca_en_soft   when ca_en_manually   else ca_en_logic;
  HIT_RST <= hit_rst_soft when hit_rst_manually else hit_rst_logic;

  rd_data_rst <= rs_start or gs_start or clk_sys_rst;  -- when start rolling shutter or global shutter, reset data readout
  jadepix_read_data : entity work.jadepix_read_data
    port map(
      clk => clk_sys,
      rst => rd_data_rst,

      clk_fpga => clk_fpga,

      start_cache     => start_cache,
      clk_cache       => clk_cache,
      clk_cache_delay => clk_cache_delay,
      is_busy_cache   => is_busy_cache,

      frame_num => rs_frame_cnt,
      row       => row_num,

      VALID_IN => VALID_IN,
      DATA_IN  => DATA_IN,

      FIFO_READ_EN => FIFO_READ_EN,
      BLK_SELECT   => BLK_SELECT,

      -- DATA FIFO
      data_fifo_rst         => data_fifo_rst,
      data_fifo_wr_clk      => data_fifo_wr_clk,
      data_fifo_wr_en       => data_fifo_wr_en,
      data_fifo_wr_din      => data_fifo_wr_din,
      data_fifo_full        => data_fifo_full,
      data_fifo_almost_full => data_fifo_almost_full
      );

end rtl;
