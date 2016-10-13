unit untMain;

{$mode objfpc}{$H+}
{$ModeSwitch advancedrecords}

interface

uses
  LCLType, Classes, SysUtils, FileUtil, Forms, Controls, Graphics, Dialogs,
  ExtCtrls, avTypes, avRes, avContnrs, avContnrsDefaults, avContext, avTess,
  avTexLoader, avMesh, mutils, avCameraController;

type
  { TmeshVert }

  TmeshVert = packed record
    vsCoord : TVec3;
    vsNormal: TVec3;
    vsTex   : TVec2;
    class function Layout: IDataLayout; static;
  end;
  ImeshVertArr = specialize IArray<TmeshVert>;
  TmeshVertArr = specialize TVerticesRec<TmeshVert>;

  { TmeshInst }

  TmeshInst = packed record
    aiTranslateTexID: TVec4;
    class function Layout: IDataLayout; static;
  end;
  ImeshInstArr = specialize IArray<TmeshInst>;
  TmeshInstArr = specialize TVerticesRec<TmeshInst>;

  IVec3Set = specialize IHashSet<TVec3>;
  TVec3Set = specialize THashSet<TVec3>;

  { TmeshProg }

  TmeshProg = class (TavProgram)
  private
    Fu_MapXStep : TUniformField;
    Fu_Map : TUniformField;
  protected
    procedure BeforeFree3D; override;
    function DoBuild: Boolean; override;
  public
    procedure SetUniforms(const MapXStep: Single; const Map: TavTexture); overload; inline;
  end;

  { TmeshGlassProg }

  TmeshGlassProg = class (TmeshProg)
  private
    Fu_BackOffsetStep : TUniformField;
    Fu_Back : TUniformField;
  protected
    procedure BeforeFree3D; override;
    function DoBuild: Boolean; override;
  public
    procedure SetUniforms(const MapXStep: Single; const BackOffsetStep: Single; const Map, Back: TavTexture); overload; //inline;
  end;

  { TmeshInstComparer }

  TmeshInstComparer = class (TInterfacedObjectEx, IComparer)
  private
    mvp: TMat4;
    FTB: Integer;
  public
    function Compare(const Left, Right): Integer;
    constructor Create(const m: TMat4; FrontToBack: Boolean);
  end;

  { TfrmMain }

  TfrmMain = class(TForm)
    ApplicationProperties1: TApplicationProperties;
    pnlOuput: TPanel;
    procedure ApplicationProperties1Idle(Sender: TObject; var Done: Boolean);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure FormPaint(Sender: TObject);
  private
    FMain: TavMainRender;
    FFBO : TavFrameBuffer;

    FVBCube         : TavVB;
    FIBCube         : TavIB;
    FVBTeapot       : TavVB;
    FIBTeapot       : TavIB;

    FVBCubeInst     : TavVB;
    FVBCubeGlassInst: TavVB;
    FVBTeapotInst   : TavVB;

    FTexCube  : TavTexture;
    FTexGlass : TavTexture;

    FBackTexure: TavTexture;

    FProg : TmeshProg;
    FGlass: TmeshGlassProg;

    FGAPI : T3DAPI;

    FFPSCounter  : Integer;
    FLastFPSTime : Int64;

    ZortLastPos : TVec3;
    cubes     : ImeshInstArr;
    teapots   : ImeshInstArr;
    glasscubes: ImeshInstArr;

    procedure Sync3DAPI;
    procedure RenderScene;
    procedure UpdateFPS;

    procedure Init;
    procedure InitInstances;

    function Convert(const meshVert: IMeshVertices): ImeshVertArr;

    procedure DoZSort;
  public
    procedure CreateWnd; override;
    procedure EraseBackground(DC: HDC); override;
  end;

var
  frmMain: TfrmMain;

implementation

uses Math;

{$R *.lfm}

{ TmeshGlassProg }

procedure TmeshGlassProg.BeforeFree3D;
begin
  inherited BeforeFree3D;
  Fu_Back := nil;
end;

function TmeshGlassProg.DoBuild: Boolean;
begin
  Result := inherited DoBuild;
  Fu_Back := GetUniformField('Back');
  Fu_BackOffsetStep := GetUniformField('BackOffsetStep');
end;

procedure TmeshGlassProg.SetUniforms(const MapXStep: Single;
  const BackOffsetStep: Single; const Map, Back: TavTexture);
begin
  SetUniform(Fu_MapXStep, MapXStep);
  SetUniform(Fu_Map, Map, Sampler_NoFilter);
  SetUniform(Fu_Back, Back, Sampler_NoFilter);
  SetUniform(Fu_BackOffsetStep, BackOffsetStep);
end;

{ TmeshInstComparer }

function TmeshInstComparer.Compare(const Left, Right): Integer;
var L: TmeshInst absolute Left;
    R: TmeshInst absolute Right;
begin
  Result := sign( (Vec(L.aiTranslateTexID.xyz,1.0)*mvp).w - (Vec(R.aiTranslateTexID.xyz,1.0)*mvp).w );
end;

constructor TmeshInstComparer.Create(const m: TMat4; FrontToBack: Boolean);
begin
  mvp := m;
  if FrontToBack then
    FTB := 1
  else
    FTB := -1;
end;

{$R 'shrScene\shaders.rc'}

{ TmeshProg }

procedure TmeshProg.BeforeFree3D;
begin
  inherited BeforeFree3D;
  Fu_MapXStep := nil;
  Fu_Map := nil;
end;

function TmeshProg.DoBuild: Boolean;
begin
  Result := inherited DoBuild;
  Fu_MapXStep := GetUniformField('MapXStep');
  Fu_Map := GetUniformField('Maps');
end;

procedure TmeshProg.SetUniforms(const MapXStep: Single; const Map: TavTexture);
begin
  SetUniform(Fu_MapXStep, MapXStep);
  SetUniform(Fu_Map, Map, Sampler_NoFilter);
end;

{ TmeshVert }

class function TmeshVert.Layout: IDataLayout;
begin
  Result := LB.Add('vsCoord', ctFloat, 3)
              .Add('vsNormal', ctFloat, 3)
              .Add('vsTex', ctFloat, 2)
              .Finish();
end;

{ TmeshInst }

class function TmeshInst.Layout: IDataLayout;
begin
  Result := LB.Add('aiTranslateTexID', ctFloat, 4).Finish();
end;

{ TfrmMain }

procedure TfrmMain.FormCreate(Sender: TObject);
begin
  Init;
end;

procedure TfrmMain.FormDestroy(Sender: TObject);
begin
  FreeAndNil(FMain);
end;

procedure TfrmMain.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = Ord('W') then
  begin
    if FGAPI = apiDX11 then
      FGAPI := apiDX11_WARP
    else
      FGAPI := apiDX11;
  end;
  if Key = VK_ESCAPE then Close;
  if Key = VK_TAB then
  begin
    if BorderStyle = bsNone then
      BorderStyle := bsSizeable
    else
      BorderStyle := bsNone;
  end;
end;

procedure TfrmMain.FormPaint(Sender: TObject);
begin
  RenderScene;
end;

procedure TfrmMain.Sync3DAPI;
begin
  FMain.Window := Handle;
  if FMain.Inited3D then
    if FMain.ActiveApi <> FGAPI then
      FMain.Free3D;
  if not FMain.Inited3D then
    FMain.Init3D(FGAPI);
end;

procedure TfrmMain.ApplicationProperties1Idle(Sender: TObject; var Done: Boolean);
begin
  Done := False;
  if FMain <> nil then FMain.InvalidateWindow;
end;

procedure TfrmMain.RenderScene;
begin
  if FMain = nil then Exit;
  Sync3DAPI;
  DoZSort;

  if FMain.Bind then
  try
    FMain.States.DepthTest := True;
    FMain.States.DepthFunc := cfLessEqual;

    FFBO.FrameRect := RectI(0, 0, ClientWidth, ClientHeight);
    FFBO.Select();
    FFBO.Clear(0, Vec(0.0,0.0,0.0,0.0));
    FFBO.ClearDS(1);

    FProg.Select();
    FProg.SetUniforms(1/10.0, FTexCube);
    FProg.SetAttributes(FVBCube, FIBCube, FVBCubeInst);
    FProg.Draw(FVBCubeInst.Vertices.VerticesCount);
    FProg.SetAttributes(FVBTeapot, FIBTeapot, FVBTeapotInst);
    FProg.Draw(FVBTeapotInst.Vertices.VerticesCount);

    FBackTexure.CopyFrom(FFBO.GetColor(0), 0, FFBO.FrameRect);

    FGlass.Select();
    FGlass.SetUniforms(1.0, FFBO.FrameRect.Size.y/5, FTexGlass, FBackTexure);
    FGlass.SetAttributes(FVBCube, FIBCube, FVBCubeGlassInst);
    FMain.States.ColorMask[0] := [];
    FGlass.Draw(FVBCubeGlassInst.Vertices.VerticesCount);
    FMain.States.ColorMask[0] := [cmRed, cmGreen, cmBlue, cmAlpha];
    FGlass.Draw(FVBCubeGlassInst.Vertices.VerticesCount);
    FFBO.BlitToWindow(0);
    FMain.Present;

    Inc(FFPSCounter);
  finally
    FMain.Unbind;
  end;

  UpdateFPS;
end;

procedure TfrmMain.UpdateFPS;
  procedure DrawFPS(const n: Integer);
  var s: String;
  begin
    if FGAPI = apiDX11_WARP then
      s := 'WARP device, FPS: ('
    else
      s := 'HARDWARE device, FPS: (';
    pnlOuput.Caption := s + IntToStr(n) + ')'
  end;
var curr, delta: Int64;
begin
  curr := FMain.Time64;
  delta := curr - FLastFPSTime;
  if delta > 500 then
  begin
    DrawFPS(Round(FFPSCounter*1000/delta));
    FLastFPSTime := curr;
    FFPSCounter := 0;
  end;
end;

procedure TfrmMain.Init;
var meshes : IavMeshes;
    mesh : IavMesh;
    meshInstances: IavMeshInstances;
begin
  FGAPI := apiDX11;

  FMain := TavMainRender.Create(nil);
  FMain.Window := Handle;
  FMain.Init3D(FGAPI);
  FMain.Camera.Eye := Vec(-5, 17, -5);
  FMain.Projection.Fov := 0.25*Pi;

  FFBO := Create_FrameBuffer(FMain, [TTextureFormat.RGBA, TTextureFormat.D32f]);

  avMesh.LoadFromFile('scene.avm', meshes, meshInstances);

  mesh := meshes['Cube.001'];
  FVBCube := TavVB.Create(FMain);
  FVBCube.Vertices := Convert(mesh.Vert) as IVerticesData;
  FIBCube := TavIB.Create(FMain);
  FIBCube.Indices := mesh.Ind as IIndicesData;
  FIBCube.CullMode := cmBack;

  mesh := meshes['teapot'];
  FVBTeapot := TavVB.Create(FMain);
  FVBTeapot.Vertices := Convert(mesh.Vert) as IVerticesData;
  FIBTeapot := TavIB.Create(FMain);
  FIBTeapot.Indices := mesh.Ind as IIndicesData;
  FIBTeapot.CullMode := cmNone;

  FProg := TmeshProg.Create(FMain);
  FProg.Load('avMesh', True, 'shrScene\!Out');
  FGlass := TmeshGlassProg.Create(FMain);
  FGlass.Load('Glass', True, 'shrScene\!Out');

  FTexCube  := TavTexture.Create(FMain);
  FTexCube.TexData := LoadTexture('tex\blocks_tst.bmp');
  FTexGlass := TavTexture.Create(FMain);
  FTexGlass.TexData := LoadTexture('tex\glass_g.bmp');

  FBackTexure := TavTexture.Create(FMain);

  InitInstances;

  with TavCameraController.Create(FMain) do
  begin
    CanMove := False;
    CanRotate := True;
  end;
end;

procedure TfrmMain.InitInstances;
var v: TmeshInst;
    w, x, y: Integer;
    cubeSet: IVec3Set;
begin
  teapots := TmeshInstArr.Create;
  cubes := TmeshInstArr.Create;
  glasscubes := TmeshInstArr.Create;

  cubeSet := TVec3Set.Create();

  w := -13;
  while (w <= 11) do
  begin
    x := -13;
    while (x <= 11) do
    begin
      if (x=8) and (w=1) then v.aiTranslateTexID.w := 2 else v.aiTranslateTexID.w := 0;
      if ((x=1) and (w=8)) or ((x=-6) and (w=-6)) then v.aiTranslateTexID.w := 1;
      v.aiTranslateTexID.xyz := Vec(x + (w mod 2)*2, 0, w+(x mod 2)*2);
      teapots.Add(v);
      x := x + 7;
    end;
    w := w + 7;
  end;

  for w := -15 to 15 do
    for x := -15 to 15 do
    begin
      if abs(x)+abs(w)<8 then
      begin
        v.aiTranslateTexID.w := 0;
        v.aiTranslateTexID.xyz := Vec(x, -7, w);
        if not cubeSet.Contains(v.aiTranslateTexID.xyz) then
        begin
          cubes.Add(v);
          cubeSet.Add(v.aiTranslateTexID.xyz);
        end;
      end;
      if abs(x)+abs(w)>5 then
      begin
        v.aiTranslateTexID.w := 2;
        v.aiTranslateTexID.xyz := Vec(x, -4, w);
        if not cubeSet.Contains(v.aiTranslateTexID.xyz) then
        begin
          cubes.Add(v);
          cubeSet.Add(v.aiTranslateTexID.xyz);
        end;
      end;
      if abs(x)+abs(w)>6 then
      begin
        v.aiTranslateTexID.w := 1;
        v.aiTranslateTexID.xyz := Vec(x, 5, w);
        if not cubeSet.Contains(v.aiTranslateTexID.xyz) then
        begin
          cubes.Add(v);
          cubeSet.Add(v.aiTranslateTexID.xyz);
        end;
      end
      else
      begin
        v.aiTranslateTexID.w := 0; // glass index
        v.aiTranslateTexID.xyz := Vec(x, 5, w);
        glasscubes.Add(v);
      end;
    end;

  for w := -7 to 7 do
    for x := -7 to 7 do
      for y := -9 to -5 do
        if Random(100) < 15 then
        begin
          v.aiTranslateTexID.w := Random(10);
          v.aiTranslateTexID.xyz := Vec(x, y, w);
          if not cubeSet.Contains(v.aiTranslateTexID.xyz) then
          begin
            cubes.Add(v);
            cubeSet.Add(v.aiTranslateTexID.xyz);
          end;
        end;

  for w := -9 to 9 do
    for x := -9 to 9 do
      for y := 4 to 12 do
        if Random(100) < 8 then
        begin
          if y = 4 then v.aiTranslateTexID.w := 0 else v.aiTranslateTexID.w := 1;
          v.aiTranslateTexID.xyz := Vec(x, y, w);
          if not cubeSet.Contains(v.aiTranslateTexID.xyz) then
          begin
            cubes.Add(v);
            cubeSet.Add(v.aiTranslateTexID.xyz);
          end;
        end;

  FVBCubeInst     := TavVB.Create(FMain);
  FVBCubeInst.Vertices := cubes as IVerticesData;
  FVBCubeGlassInst := TavVB.Create(FMain);
  FVBCubeGlassInst.Vertices := glasscubes as IVerticesData;
  FVBTeapotInst    := TavVB.Create(FMain);
  FVBTeapotInst.Vertices := teapots as IVerticesData;
end;

function TfrmMain.Convert(const meshVert: IMeshVertices): ImeshVertArr;
var i: Integer;
    v: TmeshVert;
begin
  Result := TmeshVertArr.Create;
  Result.Capacity := meshVert.Count;
  for i := 0 to meshVert.Count - 1 do
  begin
    v.vsCoord := meshVert[i].vsCoord;
    v.vsNormal := meshVert[i].vsNormal;
    v.vsTex := meshVert[i].vsTex;
    Result.Add(v);
  end;
end;

procedure TfrmMain.DoZSort;
var cmp: IComparer;
    m: TMat4;
begin
  if Len(ZortLastPos - FMain.Camera.Eye) < 4 then Exit;
  ZortLastPos := FMain.Camera.Eye;

  m := FMain.Camera.Matrix*FMain.Projection.Matrix;
  cmp := TmeshInstComparer.Create(m, False);

  cubes.Sort(cmp);
  FVBCubeInst.Invalidate;

  teapots.Sort(cmp);
  FVBTeapotInst.Invalidate;

  cmp := TmeshInstComparer.Create(m, True);
  glasscubes.Sort(cmp);
  FVBCubeGlassInst.Invalidate;
end;

procedure TfrmMain.CreateWnd;
begin
  inherited CreateWnd;
  FMain.Window := Handle;
end;

procedure TfrmMain.EraseBackground(DC: HDC);
begin
  //inherited EraseBackground(DC);
end;

end.

