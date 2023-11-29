from hconfig import *

#################################
date = "2023-11-07"
cat = True
dust = True
pressure = False
vlims = False
fstart = 0
vlims_gas = (-27 , -21.5) # g/cm^3
vlims_dust = (-32, -23.5) # g/cm^3
vlims_p = (2, 7) # P/k_b (K/cm^3)
vlims_T = (2, 8) # K
vlims_v = (-250, 1050)
spacing = 640*1e-3 # spacing of tick marks in units
# spacing = 40
fontsize = 20
unit = "kpc" # sets axes labels and units of dx (kpc or pc)
fnum = None
plt.rcParams.update({'font.family': 'Helvetica'})
plt.rcParams.update({'font.size': 20})
cloud_wind = True
debugging = False
#################################

# directory with slices
if debugging:
    basedir = f"/ix/eschneider/helena/data/debugging/{date}/"
if cloud_wind:
    basedir = f"/ix/eschneider/helena/data/cloud_wind/{date}/"
if cat:
    datadir = os.path.join(basedir, "hdf5/slice/")
else:
    datadir = os.path.join(basedir, "hdf5/raw/")
pngdir = os.path.join(basedir, "png/slice/")

if dust:
    data = ReadHDF5(datadir, nscalar=1, fnum=fnum, slice="xy", cat=cat)
else:
    data = ReadHDF5(datadir, fnum=fnum, slice="xy", cat=cat)
head = data.head
conserved = data.conserved

nx = head["dims"][0]
ny = head["dims"][-1]
dx = head["dx"][0]
if unit == "pc":
    dx *= 1e3
d_gas = data.d_cgs()
d_dust = None
p_gas = None
if dust:
    d_dust = conserved["scalar0"] * head["density_unit"]
if pressure:
    p_gas = (data.energy_cgs() - 0.5*d_gas*((data.vx_cgs())**2 + (data.vy_cgs())**2 + (data.vz_cgs())**2)) * (head["gamma"] - 1.0) 
vx = data.vx_cgs()
t_arr = data.t_cgs() / yr_in_s
T = data.T()

for i in range(fstart, len(d_gas)):

    fig, axs = plt.subplots(nrows=2, ncols=2, figsize=(25,9))
    
    # xy gas density slice
    if debugging:
        if dust:
            wh_neg = conserved["scalar0"][i][conserved["scalar0"][i]<0]
            print(wh_neg)
            if len(wh_neg) >= 1:
                print("max: ", np.amax(wh_neg))
                print("min: ", np.amin(wh_neg))
                print("\n")
            else:
                print("none\n")


    if vlims:
        im = axs[0][0].imshow(np.log10(d_gas[i].T), origin="lower", vmin=vlims_gas[0], vmax=vlims_gas[1], extent=[0, nx*dx, 0, ny*dx])
    else:
        im = axs[0][0].imshow(np.log10(d_gas[i].T), origin="lower", extent=[0, nx*dx, 0, ny*dx])
    ylabel = r'$\mathrm{log}_{10}(\rho_{gas})$ [$\mathrm{g}\mathrm{cm}^{-3}$]'
    divider = make_axes_locatable(axs[0][0])
    cax = divider.append_axes("right", size="5%", pad=0.05)
    cbar = fig.colorbar(im, ax=axs[0][0], cax=cax)
    cbar.set_label(ylabel, fontsize=fontsize)
    axs[0][0].set_xticks(np.arange(0, nx*dx, spacing))
    axs[0][0].set_yticks(np.arange(0, ny*dx, spacing))
    axs[0][0].tick_params(axis='both', which='both', direction='in', color='black', top=1, right=1, length=8)
    axs[0][0].set_title(r"Gas Density Slice", fontsize=fontsize)
    axs[0][0].set_xlabel(r"$x~$[{}]".format(unit), fontsize=fontsize)
    axs[0][0].set_ylabel(r"$y~$[{}]".format(unit), fontsize=fontsize)
    axs[0][0].text(spacing, 0.1*dx*ny, f'{round(t_arr[i]/1e6, 2)} Myr', color='white', fontsize=fontsize)
    

    # xy dust density
    if dust:
        wh_zero = np.where(d_dust[i]==0)
        d_dust[i][wh_zero] = 1e-40
        wh_neg = np.where(d_dust[i]<0)
        d_dust[i][wh_neg] = np.nan

        if vlims:
            im = axs[1][0].imshow(np.log10(d_dust[i].T), origin="lower", cmap="plasma", vmin=vlims_dust[0], vmax=vlims_dust[1], extent=[0, nx*dx, 0, ny*dx])
        else:
            im = axs[1][0].imshow(np.log10(d_dust[i].T), origin="lower", cmap="plasma", vmin=vlims_dust[0], extent=[0, nx*dx, 0, ny*dx])
        ylabel = r'$\mathrm{log}_{10}(\rho_{dust})$ [$\mathrm{g}\mathrm{cm}^{-3}$]'
        divider = make_axes_locatable(axs[1][0])
        cax = divider.append_axes("right", size="5%", pad=0.05)
        cbar = fig.colorbar(im, ax=axs[1][0], cax=cax)
        cbar.set_label(ylabel, fontsize=fontsize)
        axs[1][0].set_xticks(np.arange(0, nx*dx, spacing))
        axs[1][0].set_yticks(np.arange(0, ny*dx, spacing))
        axs[1][0].tick_params(axis='both', which='both', direction='in', color='black', top=1, right=1, length=8)
        axs[1][0].set_title(r"Dust Density Slice", fontsize=fontsize)
        axs[1][0].set_xlabel(r"$x~$[{}]".format(unit), fontsize=fontsize)
        axs[1][0].set_ylabel(r"$y~$[{}]".format(unit), fontsize=fontsize)

    # xy pressure
    if pressure:

        if vlims:
            im = axs[1][0].imshow(np.log10(p_gas[i].T/KB), origin="lower", cmap="magma", vmin=vlims_p[0], vmax=vlims_p[1], extent=[0, nx*dx, 0, ny*dx])
        else:
            im = axs[1][0].imshow(np.log10(p_gas[i].T/KB), origin="lower", cmap="magma", extent=[0, nx*dx, 0, ny*dx])
        ylabel = r'$\mathrm{log}_{10}(P_{gas}/k_B)$ [$K\,(cm^{-3})$]'
        divider = make_axes_locatable(axs[1][0])
        cax = divider.append_axes("right", size="5%", pad=0.05)
        cbar = fig.colorbar(im, ax=axs[1][0], cax=cax)
        cbar.set_label(ylabel, fontsize=fontsize)
        axs[1][0].set_xticks(np.arange(0, nx*dx, spacing))
        axs[1][0].set_yticks(np.arange(0, ny*dx, spacing))
        axs[1][0].tick_params(axis='both', which='both', direction='in', color='black', top=1, right=1, length=8)
        axs[1][0].set_title(r"Gas Pressure Slice", fontsize=fontsize)
        axs[1][0].set_xlabel(r"$x~$[{}]".format(unit), fontsize=fontsize)
        axs[1][0].set_ylabel(r"$y~$[{}]".format(unit), fontsize=fontsize)
    

    # xy temperature slice
    if vlims:
        im = axs[0][1].imshow(np.log10(T[i].T), origin="lower", cmap="inferno", vmin=vlims_T[0], vmax=vlims_T[1], extent=[0, nx*dx, 0, ny*dx])
    else:
        im = axs[0][1].imshow(np.log10(T[i].T), origin="lower", cmap="inferno", extent=[0, nx*dx, 0, ny*dx])
    ylabel = r'$\mathrm{log}_{10}(T_{gas}) [\mathrm{K}]$'
    divider = make_axes_locatable(axs[0][1])
    cax = divider.append_axes("right", size="5%", pad=0.05)
    cbar = fig.colorbar(im, ax=axs[0][1], cax=cax)
    cbar.set_label(ylabel, fontsize=fontsize)
    axs[0][1].set_xticks(np.arange(0, nx*dx, spacing))
    axs[0][1].set_yticks(np.arange(0, ny*dx, spacing))
    axs[0][1].tick_params(axis='both', which='both', direction='in', color='black', top=1, right=1, length=8)
    axs[0][1].set_title(r"Temperature Slice", fontsize=fontsize)
    axs[0][1].set_xlabel(r"$x~$[{}]".format(unit), fontsize=fontsize)
    axs[0][1].set_ylabel(r"$y~$[{}]".format(unit), fontsize=fontsize)

    # xy velocity slice
    if vlims:
        im = axs[1][1].imshow(vx[i].T*1e-5, origin="lower", vmin=vlims_v[0], vmax=vlims_v[1], extent=[0, nx*dx, 0, ny*dx])
    else:
        im = axs[1][1].imshow(vx[i].T*1e-5, origin="lower", extent=[0, nx*dx, 0, ny*dx])
    ylabel = r'$v_x$ [km/s]'
    divider = make_axes_locatable(axs[1][1])
    cax = divider.append_axes("right", size="5%", pad=0.05)
    cbar = fig.colorbar(im, ax=axs[1][1], cax=cax)
    cbar.set_label(ylabel, fontsize=fontsize)
    axs[1][1].set_xticks(np.arange(0, nx*dx, spacing))
    axs[1][1].set_yticks(np.arange(0, ny*dx, spacing))
    axs[1][1].tick_params(axis='both', which='both', direction='in', color='black', top=1, right=1, length=8)
    axs[1][1].set_title(r"x-velocity slice", fontsize=fontsize)
    axs[1][1].set_xlabel(r"$x~$[{}]".format(unit), fontsize=fontsize)
    axs[1][1].set_ylabel(r"$y~$[{}]".format(unit), fontsize=fontsize)

    fig.tight_layout()
    
    # plot and save
    save = True
    if save:
        plt.savefig(pngdir + f"{i}_slice.png", dpi=300)
    plt.close()

    print(f"Saving figure {i} of {len(d_gas)-1}.\n")
